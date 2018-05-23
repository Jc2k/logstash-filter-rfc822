require "logstash/filters/base"
require "logstash/namespace"
require "logstash/timestamp"
require "stud/interval"
require "socket" # for Socket.gethostname


class LogStash::Filters::RFC822 < LogStash::Filters::Base
  config_name "rfc822"
  
  config :lowercase_headers, :validate => :boolean, :default => true
  config :strip_attachments, :validate => :boolean, :default => false

  # For multipart messages, use the first part that has this
  # content-type as the event message.
  config :content_type, :validate => :string, :default => "text/plain"

  config :source, :validate => :string, :default => "source"

  public
  def register
    require "mail"

    @content_type_re = Regexp.new("^" + @content_type)
  end

  public
  def filter(event)
    mail = Mail.read_from_string(event.get(@source))
    
    if @strip_attachments
      mail = mail.without_attachments
    end

    if mail.parts.count == 0
      # No multipart message, just use the body as the event text
      message = mail.body.decoded
    else
      # Multipart message; use the first text/plain part we find
      part = mail.parts.find { |p| p.content_type.match @content_type_re } || mail.parts.first
      message = part.decoded
    end

    event.set("message", message)

    # Use the 'Date' field as the timestamp
    event.timestamp = LogStash::Timestamp.new(mail.date.to_time)

    # Add fields: Add message.header_fields { |h| h.name=> h.value }
    mail.header_fields.each do |header|
      # 'header.name' can sometimes be a Mail::Multibyte::Chars, get it in String form
      name = @lowercase_headers ? header.name.to_s.downcase : header.name.to_s
      # Call .decoded on the header in case it's in encoded-word form.
      # Details at:
      #   https://github.com/mikel/mail/blob/master/README.md#encodings
      #   http://tools.ietf.org/html/rfc2047#section-2
      value = transcode_to_utf8(header.decoded.to_s)

      # Assume we already processed the 'date' above.
      next if name == "Date"

      case (field = event.get(name))
      when String
        # promote string to array if a header appears multiple times
        # (like 'received')
        event.set(name, [field, value])
      when Array
        field << value
        event.set(name, field)
      when nil
        event.set(name, value)
      end
    end

    filter_matched(event)
  end
  # transcode_to_utf8 is meant for headers transcoding.
  # the mail gem will set the correct encoding on header strings decoding
  # and we want to transcode it to utf8
  def transcode_to_utf8(s)
    unless s.nil?
      s.encode(Encoding::UTF_8, :invalid => :replace, :undef => :replace)
    end
  end
end
