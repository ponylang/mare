## Fix server no longer receiving messages after a large send

After sending a large amount of data, a connection could stop delivering incoming messages — your message handler would never fire again. No error was raised and the connection was not closed; it simply went quiet, even though the client was still sending. This most often showed up on servers that keep sending while still receiving, such as echo, relay, or broadcast servers. Incoming messages are now delivered as expected.

