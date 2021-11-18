# ws_client
Easier, cleaner WebSocket clients for Crystal

WS::Client is a base class for WebSocket clients that does the work of connecting
event handler functions, and gracefully shuts down the connection when you
no longer need it. You simply declare event handlers as class methods,
and they will be connected for you.

## How To Use
add this to your `shards.yml`

```
dependencies:
  ...
  ws_client:
    github: BrucePerens/ws_client
    version: ~> 0.2.3
```
Create your own service as a child of `WS::Client`. Start by copying the file
`lib/ws_client/examples/my_client.cr` . This is a template file for your
new client, and includes a lot of the work you're instructed to do below.
Change the name of the class, and the filename, as you wish.

Add a `require` statement:
```crystal
require "ws_service"
```

Implement whichever
of the methods below that you need:
```crystal
class MyClient < WS::Client
  # This is called when binary data is received.
  def on_binary(b : Bytes)
  end

  # This is called when the connection is closed.
  def on_close(code : HTTP::WebSocket::CloseCode, message : String)
  end

  # This is called when a string data is received.
  def on_message(message : String)
  end
end
```

Create the connection using one of these constructors, which use the same
arguments as the `WebSocket` constructors. 
```crystal
  MyClient.new(
   # The URI as a `String` or `URI` object. In the form
   # method://hostname[:port]/path[?query=value[&query1=value ...]]
   # for example "wss://perens.com:5000/inform?a=1&b=2&c=Bruce
   # This contains
   # * The method, either "ws" for insecure websocket, or "wss" for secure ones
   # * The host name.
   # * The port number. You will often provide a port while testing software under
   #   development. The default is 80.
   # * The path for this service.
   # * Optional query parameters to communicate additional data to the service
   #   for authentication and initialization.
   # 
   uri : String|URI,

   # Any additional headers you wish. This argument is optional.
   # `WebSocket` will provide all necessary headers for the upgrade of the connection.
   headers : HTTP::Headers,

   # If true, this connection will run in the background and this constructor will
   # return quickly. If false (default), this constructor will block until the
   # connection is closed.
   background : Bool = false
  )

  MyClient.new(
   # The host name, as in "perens.com"
   host : String,

   # The path to the requested service, and any additional query parameters which
   # you would like to use for authentication and initialization.
   This usually begins with '/'. It might look like "/inform?a=1&b=2&c=Bruce"
   path : String,

   # The port number for the requested service, or nil. This argument is optional.
   # You will often provide a port number while testing software under development.
   # Of course, the default is 80.
   port : Int32? = nil,

   # This is a union of `nil`, `Bool`, and `OpenSSL::SSL::Context::Client`.
   # You can leave it empty, set it to `true` to say "Use TLS", or provide
   # a careflly configured SSL context with flags set as you wish. One use
   # of `OpenSSL::SSL::Context::Client` would be to use TLS but disable
   # certificate verification. This argument is optional.
   tls : HTTP::Client::TLSContext = nil,
   
   # Any additional headers you wish. This argument is optional.
   # `WebSocket` will provide all necessary headers for the upgrade of the connection.
   headers : HTTP::Headers

   # If true, this connection will run in the background and this constructor will
   # return quickly. If false (default), this constructor will block until the
   # connection is closed.
   background : Bool = false
  )
```

There are methods available to your class for sending data and managing the
connection:
```crystal
   # This will send a binary message if the argument is `Bytes`, and a textual
   # message if the argument is `String`.
   send(data : String|Bytes)

   # Close the connection.
   close(
    code : HTTP::WebSocket::CloseCode = HTTP::WebSocket::CloseCode::NormalClose,
    message : String
   )

   # Is the connection open?
   is_open? : Bool
```

The connection is automatically closed in the `finalize` method of your class.
This will gracefully close the WebSocket when your application exits, or when
your class is garbage-collected.

You can implement less-often-used methods which mirror those in WebSocket. But
the underlying software in `WebSocket` will answer pings with pongs, even if
you don't.
```crystal
   # Called upon receipt of a ping.
   def on_ping(message : String)
   end

   # Called upon receipt of a pong.
   def on_pong(message : String)
   end
```
And these less-often-used methods are available to you for sending data pings and
pongs.
```crystal
   # Send a ping.
   ping(message : String)

   # Send a pong.
   pong(message : String)
```

There is a symmtrical shard for building services, see
https://github.com/BrucePerens/ws_service .
It exports the same API as this class, but for services, and includes middleware
for effortlessly connecting it to `HTTP::Server` and common web frameworks.
