
# encoding: utf-8
require "logstash/devutils/rspec/spec_helper"
require "logstash/codecs/rfc822"
require "mail"
require "net/imap"


describe LogStash::Codecs::RFC822 do
  msg_time = Time.new
  msg_text = "foo\nbar\nbaz"
  msg_html = "<p>a paragraph</p>\n\n"

  subject do
    Mail.new do
      from     "me@example.com"
      to       "you@example.com"
      subject  "logstash imap input test"
      date     msg_time
      body     msg_text
      add_file :filename => "some.html", :content => msg_html
    end
  end

  context "with both text and html parts" do
    context "when no content-type selected" do
      it "should select text/plain part" do
        config = {}

        input = LogStash::Codecs::RFC822.new config
        input.register
        input.decode(subject.to_s) do |event|
          insist { event.get("message") } == msg_text
        end
      end
    end

    context "when text/html content-type selected" do
      it "should select text/html part" do
        config = {"content_type" => "text/html"}

        input = LogStash::Codecs::RFC822.new config
        input.register
        input.decode(subject.to_s) do |event|
          insist { event.get("message") } == msg_html
        end
      end
    end
  end

  context "when subject is in RFC 2047 encoded-word format" do
    it "should be decoded" do
      subject.subject = "=?iso-8859-1?Q?foo_:_bar?="
      config = {}

      input = LogStash::Codecs::RFC822.new config
      input.register
      input.decode(subject.to_s) do |event|
        insist { event.get("subject") } == "foo : bar"
      end
    end
  end

  context "with multiple values for same header" do
    it "should add 2 values as array in event" do
      subject.received = "test1"
      subject.received = "test2"

      config = {}

      input = LogStash::Codecs::RFC822.new config
      input.register
      input.decode(subject.to_s) do |event|
        insist { event.get("received") } == ["test1", "test2"]
      end
    end

    it "should add more than 2 values as array in event" do
      subject.received = "test1"
      subject.received = "test2"
      subject.received = "test3"

      config = {}

      input = LogStash::Codecs::RFC822.new config
      input.register
      input.decode(subject.to_s) do |event|
        insist { event.get("received") } == ["test1", "test2", "test3"]
      end
    end
  end

  context "when a header field is nil" do
    it "should parse mail" do
      subject.header['X-Custom-Header'] = nil
      config = {}

      input = LogStash::Codecs::RFC822.new config
      input.register
      input.decode(subject.to_s) do |event|
        insist { event.get("message") } == msg_text
      end
    end
  end
end
