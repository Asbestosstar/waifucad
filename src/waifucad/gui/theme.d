module waifucad.gui.theme;

struct ThemeDefaults
{
    int width;
    int height;
    const(char)* id;
    const(char)* backgroundImage;
    const(char)* navigatorBackground;
    const(char)* navigatorRailBackground;
    float ribbonPink;
    float ribbonPurple;
    float crtScanlineStrength;
    float crtMaskStrength;
}

ThemeDefaults nightcore2008Defaults() nothrow @nogc
{
    ThemeDefaults theme;
    theme.width = 1024;
    theme.height = 768;
    theme.id = "nightcore_2008".ptr;
    theme.backgroundImage = "waifus/nightcore.png".ptr;
    theme.navigatorBackground = "#171321".ptr;
    theme.navigatorRailBackground = "#100D18".ptr;
    theme.ribbonPink = 0.86f;
    theme.ribbonPurple = 0.66f;
    theme.crtScanlineStrength = 0.12f;
    theme.crtMaskStrength = 0.08f;
    return theme;
}



