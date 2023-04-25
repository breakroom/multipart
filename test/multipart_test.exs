defmodule MultipartTest do
  use ExUnit.Case
  doctest Multipart

  @boundary "==testboundary=="

  alias Multipart.Part

  test "building a message of binary parts" do
    expected_output = File.read!(file_path("/outputs/binary_parts_message.txt"))

    multipart =
      Multipart.new(@boundary)
      |> Multipart.add_part(Part.binary_body("first body"))
      |> Multipart.add_part(Part.binary_body("second body\r\n", [{"content-type", "text/plain"}]))
      |> Multipart.add_part(Part.binary_body("third body"))

    output = Multipart.body_binary(multipart)
    assert output == expected_output

    content_length = Multipart.content_length(multipart)
    assert content_length == byte_size(expected_output)
  end

  test "building a message of file parts" do
    expected_output = File.read!(file_path("outputs/file_parts_message.txt"))

    multipart =
      Multipart.new(@boundary)
      |> Multipart.add_part(Part.file_body(file_path("files/test.json")))
      |> Multipart.add_part(Part.file_body(file_path("files/test.txt")))

    output = Multipart.body_binary(multipart)
    assert output == expected_output

    content_length = Multipart.content_length(multipart)
    assert content_length == byte_size(expected_output)
  end

  test "building a message of text form-data parts" do
    expected_output = File.read!(file_path("outputs/text_form_data_parts_message.txt"))

    multipart =
      Multipart.new(@boundary)
      |> Multipart.add_part(Part.text_field("abc", "field1"))
      |> Multipart.add_part(Part.text_field("def", "field2"))

    output = Multipart.body_binary(multipart)
    assert output == expected_output

    content_length = Multipart.content_length(multipart)
    assert content_length == byte_size(expected_output)
  end

  test "building a message of file form-data parts" do
    expected_output = File.read!(file_path("outputs/file_form_data_parts_message.txt"))

    multipart =
      Multipart.new(@boundary)
      |> Multipart.add_part(Part.file_field(file_path("files/test.json"), "attachment"))
      |> Multipart.add_part(
        Part.file_field(file_path("files/test.txt"), "attachment_2", [],
          filename: "attachment.txt"
        )
      )
      |> Multipart.add_part(
        Part.file_field(file_path("files/test.txt"), "attachment_3", [],
          content_type: "application/octet-stream",
          filename: false
        )
      )

    output = Multipart.body_binary(multipart)
    assert output == expected_output

    content_length = Multipart.content_length(multipart)
    assert content_length == byte_size(expected_output)
  end

  test "building a message of file content form-data parts" do
    expected_output = File.read!(file_path("outputs/file_form_data_parts_message.txt"))

    content_json = File.read!(file_path("files/test.json"))
    content_text = File.read!(file_path("files/test.txt"))

    multipart =
      Multipart.new(@boundary)
      |> Multipart.add_part(
        Part.file_content_field(file_path("files/test.json"), content_json, "attachment")
      )
      |> Multipart.add_part(
        Part.file_content_field(file_path("files/test.txt"), content_text, "attachment_2", [],
          filename: "attachment.txt"
        )
      )
      |> Multipart.add_part(
        Part.file_content_field(file_path("files/test.txt"), content_text, "attachment_3", [],
          content_type: "application/octet-stream",
          filename: false
        )
      )

    output = Multipart.body_binary(multipart)
    assert output == expected_output

    content_length = Multipart.content_length(multipart)
    assert content_length == byte_size(expected_output)
  end

  test "building a message preserves original line breaks" do
    multipart =
      Multipart.new(@boundary)
      |> Multipart.add_part(Part.file_field(file_path("files/test-crlf.txt"), "text"))

    output = Multipart.body_binary(multipart)

    header =
      "\r\n--#{@boundary}\r\ncontent-type: text/plain\r\ncontent-disposition: form-data; name=\"text\"; filename=\"test-crlf.txt\"\r\n\r\n"

    body = File.read!(file_path("files/test-crlf.txt"))
    footer = "\r\n--#{@boundary}--\r\n"

    expected_output = header <> body <> footer
    assert output == expected_output
  end

  defp file_path(path) do
    Path.join(__DIR__, path)
  end
end
