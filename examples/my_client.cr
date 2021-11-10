require "ws_client"

class MyClient < WS::Client
  # This is called when binary data is received.
  def on_binary(b : Bytes)
    STDERR.puts "#{PROGRAM_NAME} Received binary #{b.inspect}"
  end

  # This is called when the connection is closed. It is not possible to send any
  # additional information to the WebSocket.
  def on_close(code : HTTP::WebSocket::CloseCode, message : String)
    STDERR.puts "#{PROGRAM_NAME} Closed: #{code.inspect}, #{message.inspect}"
  end

  # This is called when a string datum is received.
  def on_message(message : String)
    STDERR.puts "#{PROGRAM_NAME} Received message #{message.inspect}"
  end
end
