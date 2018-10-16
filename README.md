# nim-package-visible-types
A hacky helper lib for authoring Nim packages with package-level visiblity

### What problem does this solve?
https://forum.nim-lang.org/t/4293

### How does it work?

Create a private `types` module for your package. Put all of the types into a single `packageTypes` block like this:

``` nim
import
  package_visible_types

packageTypes:
  type
    EthereumNode* = ref object
      networkId*: uint
      chain*: AbstractChainDB
      clientId*: string
      connectionState*: ConnectionState
      keys*: KeyPair
      address*: Address
      rlpxCapabilities: seq[Capability]
      rlpxProtocols: seq[ProtocolInfo]
      listeningServer: StreamServer
      protocolStates: seq[RootRef]
      discovery: DiscoveryProtocol
      peerPool*: PeerPool

    Peer* = ref object
      transport: StreamTransport
      dispatcher: Dispatcher
      lastReqId*: int
      network*: EthereumNode
      secretsState: SecretState
      connectionState: ConnectionState
      remote*: Node
      protocolStates: seq[RootRef]
      outstandingRequests: seq[Deque[OutstandingRequest]]
      awaitedMessages: seq[FutureBase]

    OutstandingRequest = object
      id: int
      future: FutureBase
      timeoutAt: uint64

    ...
```

Even though some of the types and fields are private in the module above, `packageTypes` will
automatically define public accessors for them (intended for your private use from the package).
Furthermore, you can easily re-export the public definitions in the following way:

``` nim
import
  private/types
  
types.forwardPublicTypes

```

The scheme is currently limited to types, because private modules consisting of procs are already
forwarded relatively easy with templates.

### How does it work exactly?

1) Private types are made public, but not added to the list of forwarded types.
2) Templates are added for the private fields (read-only and var-like getters, setters, etc)

### Are there any limitations?

Unfortunately, yes.

1) It's not possible to use the object constructor syntax for objects that carry private fields.
   As a work-around, the library defines `init` templates for all of the types:

```nim
var r =  OutstandingRequest.init(id = result,
                                 future = responseFuture,
                                 timeoutAt = timeoutAt)
```

2) If an object stores a function pointer in a field, Nim will confuse the function pointer invocation
   with an application of the accessor template (resulting in an error). You can work-around the problem
   like this:
   
```nim
let result = (obj.someFuncPtr)(param, param)
```

3) The accessor templates will sometimes introduce various other general overloading issues in the context
   of other templates and generic functions.
