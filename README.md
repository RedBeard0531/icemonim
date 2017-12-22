# icemonim
Icecream monitor written in nim

For now it just parses and prints each message to stdout. It doesn't yet do
proper protocol negotiation, so it only works with the latest version of the
scheduler.

This requires a nim compiler build from the `devel` branch because it uses 
the awesome `strformat` module. If a nim version newer than 0.17.2 has been 
released, that might work too.
