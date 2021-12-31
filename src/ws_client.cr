require "http"
require "json"

module WS
end

abstract class WS::Protocol
  getter socket : HTTP::WebSocket?

  # We transmit from (at least) the main fiber and the ping fiber,
  # so lock transmit so that it is fiber-safe. Receive happens only
  # in its own fiber (which we don't presently have control of), and
  # which calls WebSocket#ping, so we're not 100% fiber-safe.
  @transmit_mutex : Mutex = Mutex.new(protection: Mutex::Protection::Reentrant)

  # Close the websocket.
  def close(code : HTTP::WebSocket::CloseCode = HTTP::WebSocket::CloseCode::NormalClosure, message : String = "goodbye")
    @transmit_mutex.synchronize do
      if (s = socket)
        s.close(code, message)
        @socket = nil
      end
    end
  end

  def finalize
    self.graceful_shutdown(message: "Graceful shutdown")
  end

  # This is meant to be called for each connection when the server is shutting down.
  # There is a potential race because I can't lock WebSocket#run from processing
  # a read or write in @fiber, while this is called from another fiber.
  def graceful_shutdown(message : String)
    close(HTTP::WebSocket::CloseCode::GoingAway, "graceful shutdown")
  end

  # Is the connection still open?
  def is_open?
    !!@socket
  end

  # This sets up the connection. I put it in an internal method so that the
  # derivative_class#connect doesn't have to call the superclass#connect.
  def internal_connect(s : HTTP::WebSocket)
    @socket = s
    s.on_binary { |bytes| self.on_binary(bytes) }
    s.on_close { |code, message| self.internal_on_close(code, message) }
    s.on_message { |string| self.on_message(string) }
    s.on_ping { |string| self.on_ping(string) }
    s.on_pong { |string| self.internal_on_pong(string) }

    # Crystal socket operations are not concurrency-safe on the same socket,
    # and there is not, at this writing (November 2021), a way to lock around
    # the WebSocket::Protocol operations in WebSocket::Run. See bug
    # https://github.com/crystal-lang/crystal/issues/11413
  end

  def internal_on_close(code : HTTP::WebSocket::CloseCode, message : String)
    if @socket
      @socket = nil
      self.on_close(code, message)
    end
  end

  # This is called when a pong is received.
  # It's overloaded in WS::Service, and that version notes the pong arrival time,
  # for timing out an unresponsive connection. Then it calls this one.
  def internal_on_pong(message : String)
    on_pong(message)
  end

  # This is called when binary data is received.
  def on_binary(b : Bytes)
    Log.error { "#{PROGRAM_NAME}: #{self.class.name}#on_binary received data, but you haven't implement the method!" }
  end

  # This is called when the connection is closed. It is not possible to send any
  # additional information to the WebSocket.
  def on_close(code : HTTP::WebSocket::CloseCode, message : String)
  end

  # This is called when a string data is received.
  def on_message(message : String)
    Log.error { "#{PROGRAM_NAME}: #{self.class.name}#on_message received a message, but you haven't implemented the method! The message was #{message.inspect}" }
  end

  # This is called when a ping is received. The pong is sent in the WebSocket code,
  # below this level.
  def on_ping(message : String)
  end

  def on_pong(message : String)
  end

  # Send a ping.
  def ping(message : String)
    @transmit_mutex.synchronize do
      if (s = socket)
        s.ping(message)
      end
    end
  end

  def run
    @socket.not_nil!.run
  end

  # Send data.
  # If data is a `String`, it's sent as a textual message.
  # If data is a `Bytes`, it's sent as a binary message.
  def send(data)
    @transmit_mutex.synchronize do
      if (s = socket)
        s.send(data)
      end
    end
  end
end

class WS::Client < WS::Protocol
end

module WS::JSON
  getter uuid : UUID? = nil
 
  def on_message(message : String)
    begin
      json = ::JSON.parse(message)
    rescue
      # bad client data.
      Log.error { "WS::Client #on_message couldn't parse message \"#{message.inspect}\" to JSON." }
      return
    end

    type = json["type"]?.try &.as_s?
    data = json["data"]?
  
    if type.is_a?(String) && data.is_a?(::JSON::Any)
      case type
      when "$text$"
        on_text(data.to_s)
      when "$uuid$"
        if (uuid_json = data)
          begin
            @uuid = UUID.new(uuid_json.as_s)
          rescue
            @uuid = nil
          end
        end
      end
    end
  end

  def on_text(message : String)
    STDERR.puts "#{PROGRAM_NAME} Received text: #{message}"
  end

  def on_json(type : String, data : ::JSON::Any)
    STDERR.puts "#{PROGRAM_NAME} Received JSON #{type}: #{data.inspect}"
  end

  def send_json(type : String, data)
    if !data.responds_to?(:to_json)
      RuntimeError.new(
       "#{self.class.name}#send_json: The #{data.class.name} provided as data doesn't implement a to_json method."
      )
    end
    send({type: type, data: data}.to_json)
  end

  def send_text(message : String)
    # There is no requirement for you to use odd characters in the type argument
    # in your own code. They are just here so that our text message type won't
    # collide with user-defined types.
    send_json("$text$", message)
  end
end

abstract class WS::Client::JSON < WS::Client
  include WS::JSON
end
# See https://github.com/BrucePerens/ws_service for the service version, and
# middleware.
