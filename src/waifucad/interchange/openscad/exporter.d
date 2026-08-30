module waifucad.interchange.openscad.exporter;

import core.stdc.stdio : FILE, fopen, fclose, fprintf;
import core.stdc.string : strcmp;
import waifucad.kernel.model : Model;
import waifucad.kernel.types : FeatureKind, ModellingRole, ExactGeometryStatus, BoundingBox;
import waifucad.mesh.types : MeshArena, MeshId, MeshVec3;
import waifucad.mesh.tessellate_brep : tessellateBRepSolid;
import waifucad.mesh.payload_io : meshFromPolyhedronPayload;
import waifucad.interchange.openscad.options : OpenScadExportOptions, OpenScadExportScope, OpenScadExportFallback;

private int makeBoundsMesh(MeshArena* arena, const BoundingBox* b, MeshId* result) nothrow @nogc
{
    if (arena is null || b is null || result is null || !b.valid) return 1;
    auto id = arena.beginMesh();
    if (id == 0) return 2;
    MeshVec3[8] p = [
        MeshVec3(b.minX,b.minY,b.minZ), MeshVec3(b.maxX,b.minY,b.minZ),
        MeshVec3(b.maxX,b.maxY,b.minZ), MeshVec3(b.minX,b.maxY,b.minZ),
        MeshVec3(b.minX,b.minY,b.maxZ), MeshVec3(b.maxX,b.minY,b.maxZ),
        MeshVec3(b.maxX,b.maxY,b.maxZ), MeshVec3(b.minX,b.maxY,b.maxZ)
    ];
    foreach (point; p) if (!arena.addVertex(id,point)) return 3;
    uint[36] idx=[0,2,1,0,3,2,4,5,6,4,6,7,0,1,5,0,5,4,1,2,6,1,6,5,2,3,7,2,7,6,3,0,4,3,4,7];
    foreach(i;0..12) if(!arena.addTriangle(id,idx[i*3],idx[i*3+1],idx[i*3+2])) return 4;
    *result=id;
    return 0;
}

private void transformedPoint(const MeshArena* arena, MeshId meshId, uint index,
                              const OpenScadExportOptions* options, MeshVec3* output) nothrow @nogc
{
    auto mesh=arena.mesh(meshId);
    auto p=arena.vertices[mesh.firstVertex+index];
    double cx=0.0,cy=0.0,cz=0.0;
    if(options.centreEachBody && mesh.bounds.valid)
    {
        cx=(mesh.bounds.minimum.x+mesh.bounds.maximum.x)*0.5;
        cy=(mesh.bounds.minimum.y+mesh.bounds.maximum.y)*0.5;
        cz=(mesh.bounds.minimum.z+mesh.bounds.maximum.z)*0.5;
    }
    output.x=(p.x-cx)*options.unitScale;
    output.y=(p.y-cy)*options.unitScale;
    output.z=(p.z-cz)*options.unitScale;
}

private int writeMesh(FILE* file, const MeshArena* arena, MeshId meshId, const(char)* name,
                      uint bodyIndex, const OpenScadExportOptions* options) nothrow @nogc
{
    auto mesh=arena.mesh(meshId);
    if(file is null || mesh is null) return 1;
    auto precision=options.precision > 17 ? 17u : options.precision;
    if(options.emitSourceNames)
        fprintf(file,"// source-feature: %s\n",name);
    if(options.emitStatistics)
        fprintf(file,"// vertices=%u triangles=%u closed_hint=%u source_mesh_format=%s\n",
                mesh.vertexCount,mesh.triangleCount,mesh.closedHint?1u:0u,mesh.sourceFormat.ptr());

    // These comments are a dependency-free WaifuCAD round-trip channel while
    // the following polyhedron() remains ordinary, valid OpenSCAD source.
    if(options.emitRoundTripMetadata)
    {
        fprintf(file,"// wc-body-begin %s\n",name);
        foreach(i;0..mesh.vertexCount)
        {
            MeshVec3 p;
            transformedPoint(arena,meshId,i,options,&p);
            fprintf(file,"// wc-vertex %.*f %.*f %.*f\n",cast(int)precision,p.x,cast(int)precision,p.y,cast(int)precision,p.z);
        }
        foreach(i;0..mesh.triangleCount)
        {
            auto t=arena.triangles[mesh.firstTriangle+i];
            if(options.reverseWinding)
                fprintf(file,"// wc-triangle %u %u %u\n",t.a,t.c,t.b);
            else
                fprintf(file,"// wc-triangle %u %u %u\n",t.a,t.b,t.c);
        }
        fprintf(file,"// wc-body-end\n");
    }

    if(options.oneModulePerBody)
        fprintf(file,"module wc_body_%u() {\n",bodyIndex);
    fprintf(file,"  polyhedron(points=[\n");
    foreach(i;0..mesh.vertexCount)
    {
        MeshVec3 p;
        transformedPoint(arena,meshId,i,options,&p);
        fprintf(file,"    [%.*f,%.*f,%.*f]%s\n",cast(int)precision,p.x,cast(int)precision,p.y,cast(int)precision,p.z,
                i+1<mesh.vertexCount?",".ptr:"".ptr);
    }
    fprintf(file,"  ], faces=[\n");
    foreach(i;0..mesh.triangleCount)
    {
        auto t=arena.triangles[mesh.firstTriangle+i];
        uint a=t.a,b=t.b,c=t.c;
        if(options.reverseWinding){auto swap=b;b=c;c=swap;}
        fprintf(file,"    [%u,%u,%u]%s\n",a,b,c,i+1<mesh.triangleCount?",".ptr:"".ptr);
    }
    fprintf(file,"  ], convexity=%u);\n",options.convexity);
    if(options.oneModulePerBody)
    {
        fprintf(file,"}\n");
        if(options.wrapInRender)
            fprintf(file,"render(convexity=%u) wc_body_%u();\n\n",options.convexity,bodyIndex);
        else
            fprintf(file,"wc_body_%u();\n\n",bodyIndex);
    }
    return 0;
}

private bool featureWanted(Model* model, size_t index, const OpenScadExportOptions* options) nothrow @nogc
{
    auto f=&model.features[index];
    final switch(options.exportScope)
    {
        case OpenScadExportScope.namedFeature:
            return f.name.equals(options.featureName.ptr());
        case OpenScadExportScope.allDumbBodies:
            return f.role==ModellingRole.dumbBody || f.meshId!=0;
        case OpenScadExportScope.allBodies:
            return f.role==ModellingRole.dumbBody || f.meshId!=0 || model.exactStatus[index]==ExactGeometryStatus.exact;
    }
}

int exportOpenScad(Model* model, const(char)* path, const OpenScadExportOptions* suppliedOptions) nothrow @nogc
{
    if(model is null || path is null) return 1;
    OpenScadExportOptions defaults; defaults.setDefaults();
    auto options=suppliedOptions is null?&defaults:suppliedOptions;
    if(options.exportScope==OpenScadExportScope.namedFeature && options.featureName.length==0) return 2;
    auto file=fopen(path,"wb".ptr);
    if(file is null) return 3;

    if(options.emitHeader)
    {
        fprintf(file,"// WaifuCAD dumb-body OpenSCAD export\n");
        fprintf(file,"// Parametric sketches/features were intentionally flattened.\n");
        fprintf(file,"// Re-import creates dumb mesh bodies, not reconstructed history.\n\n");
    }
    if(options.emitResolutionVariables)
    {
        if(options.fn!=0) fprintf(file,"$fn=%u;\n",options.fn);
        if(options.fa>0.0) fprintf(file,"$fa=%.9g;\n",options.fa);
        if(options.fs>0.0) fprintf(file,"$fs=%.9g;\n",options.fs);
        fprintf(file,"\n");
    }

    uint bodyCount=0;
    int failure=0;
    foreach(i;0..model.featureCount)
    {
        if(!featureWanted(model,i,options)) continue;
        auto feature=&model.features[i];
        MeshArena scratch;
        scratch.clear();
        const(MeshArena)* sourceArena=null;
        MeshId meshId=0;

        if(feature.meshId!=0)
        {
            sourceArena=&model.dumbMeshes;
            meshId=feature.meshId;
        }
        else if(feature.kind==FeatureKind.polyhedron && feature.payload.length!=0 && feature.payload2.length!=0)
        {
            auto rc=meshFromPolyhedronPayload(&scratch,feature.payload.ptr(),feature.payload2.ptr(),&meshId);
            if(rc!=0){failure=10+rc;break;}
            sourceArena=&scratch;
        }
        else if(model.exactStatus[i]==ExactGeometryStatus.exact)
        {
            OpenScadExportOptions tessOptions=*options;
            tessOptions.unitScale=1.0;
            tessOptions.centreEachBody=false;
            tessOptions.reverseWinding=false;
            auto rc=tessellateBRepSolid(&scratch,&model.exactGeometry,model.exactSolidIds[i],&tessOptions,&meshId);
            if(rc!=0){failure=20+rc;break;}
            sourceArena=&scratch;
        }
        else if(options.fallback==OpenScadExportFallback.boundingBox && model.previewBounds[i].valid)
        {
            auto rc=makeBoundsMesh(&scratch,&model.previewBounds[i],&meshId);
            if(rc!=0){failure=60+rc;break;}
            sourceArena=&scratch;
            fprintf(file,"// WARNING: %s exported from preview bounding box fallback.\n",feature.name.ptr());
        }
        else
        {
            failure=80;
            break;
        }

        ++bodyCount;
        auto rc=writeMesh(file,sourceArena,meshId,feature.name.ptr(),bodyCount,options);
        if(rc!=0){failure=90+rc;break;}
    }
    if(bodyCount==0 && failure==0) failure=100;
    fclose(file);
    return failure;
}



