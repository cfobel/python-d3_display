class EchoController
    constructor: (@context, @uri) ->
        @last_response = null

    send: (sock, message) -> sock.send(message)

    serialize: (message) -> message

    deserialize: (message) -> message

    do_request: (message, on_recv) =>
        try
            sock = @context.socket(nullmq.REQ)
            sock.connect(@uri)
            @send(sock, @serialize(message))
            obj = @
            _on_recv = (value) ->
                value = obj.deserialize(value)
                on_recv(value)
                sock.close()
            sock.recv(_on_recv)
        catch error
            alert(error)


class EchoJsonController extends EchoController
    serialize: (javascript_obj) -> JSON.stringify(javascript_obj)

    deserialize: (json_string) ->
        try
            value = JSON.parse(json_string)
        catch error
            alert(error)
            value = null
        return value


@EchoController = EchoController
@EchoJsonController = EchoJsonController
