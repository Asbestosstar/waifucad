module waifucad.brep.tolerance;

import core.stdc.math : fabs, sqrt;
import waifucad.brep.types : BRepArena, BRepId, BRepVec3;

/* Central tolerance policy for exact-kernel operations that need tolerant
 * comparisons. Tolerance permits robust decisions; it never changes a
 * preview/mesh result into an exact B-rep result. */
struct BRepTolerancePolicy
{
    double absoluteLength;
    double angular;
    double parameter;

    void setDefaults() nothrow @nogc
    {
        absoluteLength = 1.0e-8;
        angular = 1.0e-10;
        parameter = 1.0e-10;
    }
}

BRepTolerancePolicy defaultTolerancePolicy() nothrow @nogc
{
    BRepTolerancePolicy result;
    result.setDefaults();
    return result;
}

private bool finiteScalar(double value) nothrow @nogc
{
    return value == value && value <= double.max && value >= -double.max;
}

bool finitePoint(BRepVec3 p) nothrow @nogc
{
    return finiteScalar(p.x) && finiteScalar(p.y) && finiteScalar(p.z);
}

double pointDistance(BRepVec3 a, BRepVec3 b) nothrow @nogc
{
    auto dx = a.x-b.x, dy = a.y-b.y, dz = a.z-b.z;
    return sqrt(dx*dx+dy*dy+dz*dz);
}

bool withinLengthTolerance(double a, double b, const(BRepTolerancePolicy)* policy = null) nothrow @nogc
{
    auto p = policy is null ? defaultTolerancePolicy() : *policy;
    return fabs(a-b) <= p.absoluteLength;
}

bool coincidentPoints(BRepVec3 a, BRepVec3 b, const(BRepTolerancePolicy)* policy = null) nothrow @nogc
{
    auto p = policy is null ? defaultTolerancePolicy() : *policy;
    return finitePoint(a) && finitePoint(b) && pointDistance(a,b) <= p.absoluteLength;
}

/* Conservative healing primitive: snap geometric positions of already
 * distinct topological vertices when they are within tolerance. It does not
 * merge vertex IDs or coedge rings, because that requires a topology Euler
 * operation and persistent-lineage bookkeeping. */
uint snapCoincidentVertexGeometry(BRepArena* arena, const(BRepTolerancePolicy)* policy = null) nothrow @nogc
{
    if(arena is null) return 0;
    auto p = policy is null ? defaultTolerancePolicy() : *policy;
    uint snapped = 0;
    foreach(i; 0 .. arena.vertexCount)
    {
        auto first = &arena.vertices[i];
        if(!finitePoint(first.point)) continue;
        foreach(j; i+1 .. arena.vertexCount)
        {
            auto second = &arena.vertices[j];
            if(!finitePoint(second.point)) continue;
            if(pointDistance(first.point,second.point) <= p.absoluteLength)
            {
                second.point = first.point;
                if(second.tolerance < p.absoluteLength) second.tolerance = p.absoluteLength;
                ++snapped;
            }
        }
    }
    return snapped;
}

/* Returns the maximum recorded vertex tolerance and rejects non-finite
 * geometry. This is a small diagnostic used by import/healing and tests. */
bool toleranceDiagnostics(const(BRepArena)* arena, double* maximumVertexTolerance) nothrow @nogc
{
    if(arena is null || maximumVertexTolerance is null) return false;
    double maximum = 0.0;
    foreach(i; 0 .. arena.vertexCount)
    {
        auto vertex = &arena.vertices[i];
        if(!finitePoint(vertex.point) || !finiteScalar(vertex.tolerance)) return false;
        if(vertex.tolerance > maximum) maximum = vertex.tolerance;
    }
    *maximumVertexTolerance = maximum;
    return true;
}

