defmodule Multipart do
  @moduledoc """
  `Multipart` constructs multipart messages.

  It aims to produce multipart messages that are compatible with [RFC
  2046](https://tools.ietf.org/html/rfc2046#section-5.1) for general use, and
  [RFC 7578](https://tools.ietf.org/html/rfc7578) for constructing
  `multipart/form-data` requests.
  """

  alias Multipart.Part

  defstruct boundary: nil, parts: []

  @type t :: %__MODULE__{
          boundary: String.t(),
          parts: list(Part.t())
        }

  @crlf "\r\n"
  @separator "--"

  @doc """
  Create a new `Multipart` request.

  Pass in the boundary as the first argument to set it explicitly, otherwise
  it will default to a random 16 character alphanumeric string padded by `==`
  on either side.
  """
  @spec new(String.t()) :: t()
  def new(boundary \\ generate_boundary()) do
    %__MODULE__{boundary: boundary}
  end

  @doc """
  Adds a part to the `Multipart` message.
  """
  @spec add_part(t(), Multipart.Part.t()) :: t()
  def add_part(%__MODULE__{parts: parts} = multipart, %Part{} = part) do
    %__MODULE__{multipart | parts: parts ++ [part]}
  end

  @doc """
  Returns a `Stream` of the `Multipart` message body.
  """
  @spec body_stream(t()) :: Enum.t()
  def body_stream(%__MODULE__{boundary: boundary, parts: parts}) do
    parts
    |> Enum.map(&part_stream(&1, boundary))
    |> Stream.concat()
    |> Stream.concat([final_delimiter(boundary)])
  end

  @doc """
  Returns a binary of the `Multipart` message body.

  This uses `body_stream/1` under the hood.
  """
  @spec body_binary(t()) :: binary()
  def body_binary(%__MODULE__{} = multipart) do
    multipart
    |> body_stream()
    |> Enum.join("")
  end

  @doc """
  Returns the Content-Type header for the `Multipart` message.

      iex> multipart = Multipart.new("==abc123==")
      iex> Multipart.content_type(multipart, "multipart/mixed")
      "multipart/mixed; boundary=\\"==abc123==\\""
  """
  @spec content_type(t(), String.t()) :: String.t()
  def content_type(%__MODULE__{boundary: boundary}, mime_type) do
    [mime_type, "boundary=\"#{boundary}\""]
    |> Enum.join("; ")
  end

  @doc """
  Returns the length of the `Multipart` message in bytes.

  It uses the `content_length` property in each of the message parts to
  calculate the length of the multipart message without reading the entire
  body into memory. `content_length` is set on the `Multipart.Part` by the
  constructor functions when possible, such as when the in-memory binary
  or the file on disk can be inspected.

  This will throw an error if any of the parts does not have `content_length`
  defined.
  """
  @spec content_length(t()) :: pos_integer()
  def content_length(%__MODULE__{parts: parts, boundary: boundary}) do
    final_delimiter_length =
      final_delimiter(boundary)
      |> Enum.join("")
      |> byte_size()

    parts
    |> Enum.with_index()
    |> Enum.reduce(0, fn {%Part{} = part, index}, total ->
      case part_content_length(part, boundary) do
        cl when is_integer(cl) ->
          cl + total

        nil ->
          throw("Part at index #{index} has nil content_length")
      end
    end)
    |> Kernel.+(final_delimiter_length)
  end

  @doc """
  Returns `Multipart` for a binary message body.
  """
  @spec decode(String.t(), String.t()) :: {:ok, t()} | :error
  def decode(boundary, @crlf <> data),
    do: decode_parts(boundary, byte_size(boundary), data, [])

  def decode(_data), do: :error

  defp part_stream(%Part{} = part, boundary) do
    Stream.concat([part_delimiter(boundary), part_headers(part), part_body_stream(part)])
  end

  defp part_content_length(%Part{content_length: content_length} = part, boundary) do
    if is_integer(content_length) do
      Enum.concat(part_delimiter(boundary), part_headers(part))
      |> Enum.reduce(0, fn str, acc ->
        byte_size(str) + acc
      end)
      |> Kernel.+(content_length)
    else
      nil
    end
  end

  defp part_delimiter(boundary) do
    [@crlf, @separator, boundary, @crlf]
  end

  defp final_delimiter(boundary) do
    [@crlf, @separator, boundary, @separator, @crlf]
  end

  defp part_headers(%Part{headers: headers}) do
    headers
    |> Enum.flat_map(fn {k, v} ->
      ["#{k}: #{v}", @crlf]
    end)
    |> List.insert_at(-1, @crlf)
  end

  defp part_body_stream(%Part{body: body}) when is_binary(body) do
    [body]
  end

  defp part_body_stream(%Part{body: body}) when is_list(body) do
    body
  end

  defp part_body_stream(%Part{body: %type{} = body}) when type in [Stream, File.Stream] do
    body
  end

  defp generate_boundary() do
    token =
      16
      |> :crypto.strong_rand_bytes()
      |> Base.encode16(case: :lower)

    "==#{token}=="
  end

  defp decode_parts(boundary, boundary_size, data, parts) do
    case data do
      <<@separator, ^boundary::binary-size(boundary_size), @separator, _rest::binary>> ->
        {:ok, %__MODULE__{new(boundary) | parts: Enum.reverse(parts)}}

      <<@separator, ^boundary::binary-size(boundary_size), @crlf, rest::binary>> ->
        with {:ok, part, rest} <- decode_part(rest) do
          decode_parts(boundary, boundary_size, rest, [part | parts])
        end
    end
  end

  defp decode_part(data) do
    with {:ok, headers, rest} <- decode_headers(data, []),
         {:ok, body, rest} <- decode_body(rest, "") do
      {:ok, %Part{headers: headers, body: body, content_length: byte_size(body)}, rest}
    end
  end

  defp decode_headers(<<@crlf, rest::binary>>, headers),
    do: {:ok, Enum.reverse(headers), rest}

  defp decode_headers(data, headers) do
    with {:ok, header, rest} <- decode_header(data, "") do
      decode_headers(rest, [header | headers])
    end
  end

  defp decode_header(<<@crlf, rest::binary>>, header),
    do: {:ok, String.split(header, ": ", parts: 2) |> List.to_tuple(), rest}

  defp decode_header(<<data::binary-size(1), rest::binary>>, header),
    do: decode_header(rest, header <> data)

  defp decode_header(_data, _headers), do: :error

  defp decode_body(<<@crlf, @separator, rest::binary>>, body),
    do: {:ok, body, @separator <> rest}

  defp decode_body(<<data::binary-size(1), rest::binary>>, body),
    do: decode_body(rest, body <> data)

  defp decode_body(_data, _body), do: :error
end
