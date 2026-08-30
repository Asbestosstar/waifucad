module waifucad.ai.protocol;

/*
 * Provider-neutral AI boundary. Providers exchange owned UTF-8 payloads through
 * a C ABI and never receive raw model or geometry-kernel pointers.
 * Model inspection is expressed through the read-only SCL/WCS getter schema.
 */
enum WC_AI_PROTOCOL_V1 = 1u;

enum AiActionKind : ubyte
{
    inspectDocument,
    proposeScl,
    validateScl,
    executeScl,
    captureViewport
}

enum AiCapability : ulong
{
    inspectDocument = 1UL << 0,
    proposeScl = 1UL << 1,
    validateScl = 1UL << 2,
    executeScl = 1UL << 3,
    captureViewport = 1UL << 4
}

struct AiRequestV1
{
    uint abiVersion;
    ulong requestId;
    AiActionKind kind;
    const(char)* utf8Payload;
    size_t payloadLength;
}

struct AiResponseV1
{
    uint abiVersion;
    ulong requestId;
    int status;
    const(char)* utf8Payload;
    size_t payloadLength;
}

/*
 * The provider owns response payload storage until releaseResponse is called.
 * This permits providers implemented with C/C++/Rust/Ruby/JNI/etc. to use their
 * native allocator without introducing that allocator into BetterC kernel code.
 */
extern(C) alias AiInvokeV1Fn = int function(const(AiRequestV1)* request, AiResponseV1* response) nothrow;
extern(C) alias AiReleaseResponseV1Fn = void function(AiResponseV1* response) nothrow;

struct AiProviderV1
{
    uint abiVersion;
    const(char)* providerId;
    const(char)* displayName;
    ulong capabilities;
    size_t maximumRequestBytes;
    size_t maximumResponseBytes;
    AiInvokeV1Fn invoke;
    AiReleaseResponseV1Fn releaseResponse;
}

bool providerSupports(const(AiProviderV1)* provider, AiCapability capability) nothrow @nogc
{
    return provider !is null && provider.abiVersion == WC_AI_PROTOCOL_V1 &&
           (provider.capabilities & cast(ulong)capability) != 0;
}

