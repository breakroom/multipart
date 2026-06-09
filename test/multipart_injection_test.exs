defmodule MultipartInjectionTest do
  use ExUnit.Case, async: true

  alias Multipart.Part

  @boundary "==testboundary=="

  describe "content-disposition directive injection" do
    test "a quote in filename cannot break out to inject a directive" do
      multipart =
        Multipart.new(@boundary)
        |> Multipart.add_part(
          Part.file_content_field("/tmp/x.txt", "data", "f", [],
            content_type: false,
            filename: ~s(a"; name="evil)
          )
        )

      output = Multipart.body_binary(multipart)

      # The quote must be percent-encoded, not passed through verbatim.
      assert output =~ "%22"
      # No injected second `name=` directive may appear.
      refute output =~ ~s(name="evil")
    end

    test "CRLF in a field name cannot inject a new header" do
      multipart =
        Multipart.new(@boundary)
        |> Multipart.add_part(Part.text_field("v", "x\r\nX-Injected: yes"))

      output = Multipart.body_binary(multipart)

      assert output =~ "%0D%0A"
      # The CRLF is encoded, so "X-Injected" can only survive inside the quoted
      # value, never as its own header line (preceded by a real CRLF).
      refute output =~ "\r\nX-Injected: yes"
    end

    test "a trailing backslash cannot escape the structural closing quote" do
      # In RFC 2045/2183 (MIME/email) quoted-string semantics, a `\"` is an
      # escaped quote, so a value ending in a backslash would escape the
      # library's own closing quote and absorb the following directive.
      multipart =
        Multipart.new(@boundary)
        |> Multipart.add_part(
          Part.file_content_field("/tmp/x.txt", "data", "evil\\", [],
            content_type: false,
            filename: "secret.txt"
          )
        )

      output = Multipart.body_binary(multipart)

      # The backslash must be percent-encoded, not left to escape the quote.
      assert output =~ "%5C"
      # The name value must terminate cleanly so the filename stays a distinct
      # directive: no `\"` (backslash immediately before a structural quote).
      refute output =~ "\\\""
      assert output =~ ~s(filename="secret.txt")
    end
  end

  describe "boundary validation" do
    test "CRLF in a custom boundary is rejected" do
      assert_raise ArgumentError, fn -> Multipart.new("a\r\nb") end
    end

    test "a quote in a custom boundary is rejected" do
      assert_raise ArgumentError, fn -> Multipart.new(~s(a"b)) end
    end

    test "conforming boundaries are still accepted" do
      assert %Multipart{} = Multipart.new("==testboundary==")
      assert %Multipart{} = Multipart.new("myboundary")
    end
  end

  describe "generic header CRLF rejection" do
    test "CRLF in a header value raises when serialized" do
      multipart =
        Multipart.new(@boundary)
        |> Multipart.add_part(Part.binary_body("body", [{"x-custom", "a\r\nX-Injected: yes"}]))

      assert_raise ArgumentError, fn -> Multipart.body_binary(multipart) end
    end

    test "CRLF in a header name raises when serialized" do
      multipart =
        Multipart.new(@boundary)
        |> Multipart.add_part(Part.binary_body("body", [{"x-custom\r\nX-Injected", "yes"}]))

      assert_raise ArgumentError, fn -> Multipart.body_binary(multipart) end
    end
  end
end
