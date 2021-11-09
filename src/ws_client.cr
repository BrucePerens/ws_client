module WS
end
abstract class WS::Protocol
  getter socket : HTTP::WebSocket?

  # We transmit from (at least) the main fiber and the ping fiber,
  # so lock transmit so that it is fiber-safe. Receive happens only
  # in its own fiber (which we don't presently have control of), and
  # which calls WebSocket#ping, so we're not 100% fiber-safe.
  @transmit_mutex : Mutex = Mutex.new

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
    s.on_close { |code, message| self.internal_close(code, message) }
    s.on_message { |string| self.on_message(string) }
    s.on_ping { |string| self.on_ping(string) }
    s.on_pong { |string| self.internal_on_pong(string) }

    # Crystal socket operations are not concurrency-safe on the same socket,
    # and there is not, at this writing (November 2021), a way to lock around
    # the WebSocket::Protocol operations in WebSocket::Run. See bug
    # https://github.com/crystal-lang/crystal/issues/11413
  end

  def internal_close(code : HTTP::WebSocket::CloseCode, message : String)
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
    Log.error { "#{PROGRAM_NAME}: #{self.class.name}#on_binary received data, implement the method!" }
  end

  # This is called when the connection is closed. It is not possible to send any
  # additional information to the WebSocket.
  def on_close(code : HTTP::WebSocket::CloseCode, message : String)
  end

  # This is called when a string data is received.
  def on_message(message : String)
    Log.error { "#{PROGRAM_NAME}: #{self.class.name}#on_binary received message #{message.inspect}, implement the method!" }
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

# Client version of WS::Protocol.
class WS::Client < WS::Protocol
  def initialize(uri : String|URI, headers : HTTP::Headers = HTTP::Headers.new)
    socket = HTTP::WebSocket.new(uri: uri)
    internal_connect(socket)
  end

  def initialize(host : String, path : String, port : Int32? = nil, tls : HTTP::Client::TLSContext = nil, headers : HTTP::Headers = HTTP::Headers.new)
    socket = HTTP::WebSocket.new(host, path, port, tls, headers)
    internal_connect(socket)
  end
end

# See https://github.com/BrucePerens/ws_service for the service version, and
# middleware.
