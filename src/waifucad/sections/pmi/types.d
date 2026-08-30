module waifucad.sections.pmi.types;

import waifucad.core.fixed_string : FixedString64, FixedString256;
import waifucad.kernel.types : EntityId;

/* Product and Manufacturing Information kept separately from modelling history. */
enum PmiAnnotationKind : ubyte
{
    none,
    note,
    linearDimension,
    angularDimension,
    radialDimension,
    diameterDimension,
    datumFeature,
    featureControlFrame,
    surfaceTexture,
    weldSymbol,
    centreline,
    annotationPlane
}

struct PmiAssociation
{
    EntityId featureId;
    uint subentityKind;
    uint subentityIndex;
}

struct PmiAnnotation
{
    uint id;
    PmiAnnotationKind kind;
    FixedString64 name;
    FixedString256 text;
    PmiAssociation association;
    bool associative;
    bool visible;
}



