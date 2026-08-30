module waifucad.gui.navigation;

enum NavigationAction : ubyte
{
    none,
    panForward,
    panBackward,
    panLeft,
    panRight,
    orbitDrag,
    panDrag,
    zoom,
    fitView
}

struct Vec3
{
    double x;
    double y;
    double z;
}

struct CameraState
{
    Vec3 target;
    Vec3 viewRight;
    Vec3 viewUp;
    double distance;
    double keyboardPanStep;

    void applyKeyboardPan(NavigationAction action) nothrow @nogc
    {
        double right = 0.0;
        double up = 0.0;
        final switch (action)
        {
            case NavigationAction.panForward: up = 1.0; break;
            case NavigationAction.panBackward: up = -1.0; break;
            case NavigationAction.panLeft: right = -1.0; break;
            case NavigationAction.panRight: right = 1.0; break;
            case NavigationAction.none:
            case NavigationAction.orbitDrag:
            case NavigationAction.panDrag:
            case NavigationAction.zoom:
            case NavigationAction.fitView:
                return;
        }
        auto scale = keyboardPanStep * (distance > 1.0 ? distance : 1.0);
        target.x += (viewRight.x * right + viewUp.x * up) * scale;
        target.y += (viewRight.y * right + viewUp.y * up) * scale;
        target.z += (viewRight.z * right + viewUp.z * up) * scale;
    }
}



