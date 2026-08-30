module waifucad.mods.api;

import waifucad.sections.api : SectionDescriptorV1;

enum WC_MOD_ABI_V1 = 1u;

extern(C) alias RegisterSectionFn = int function(const SectionDescriptorV1*) nothrow @nogc;
extern(C) alias RegisterSclCommandFn = int function(const(char)*, void*) nothrow @nogc;
extern(C) alias ModLoadFn = int function(const ModHostV1*) nothrow @nogc;
extern(C) alias ModUnloadFn = void function() nothrow @nogc;

struct ModHostV1
{
    uint abiVersion;
    RegisterSectionFn registerSection;
    RegisterSclCommandFn registerSclCommand;
}

struct ModDescriptorV1
{
    uint abiVersion;
    const(char)* id;
    const(char)* name;
    const(char)* versionText;
    ModLoadFn load;
    ModUnloadFn unload;
}

extern(C) alias WaifuCadModEntryV1 = ModDescriptorV1* function() nothrow @nogc;



