/*
Copyright (c) 2018-2025 Rafał Ziemniewski, Timur Gafarov

Boost Software License - Version 1.0 - August 17th, 2003
Permission is hereby granted, free of charge, to any person or organization
obtaining a copy of the software and accompanying documentation covered by
this license (the "Software") to use, reproduce, display, distribute,
execute, and transmit the Software, and to prepare derivative works of the
Software, and to permit third-parties to whom the Software is furnished to
do so, all subject to the following:

The copyright notices in the Software and this entire statement, including
the above license grant, this restriction and the following disclaimer,
must be included in all copies of the Software, in whole or in part, and
all derivative works of the Software, unless such copies or derivative
works are solely in the form of machine-executable object code generated by
a source language processor.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE, TITLE AND NON-INFRINGEMENT. IN NO EVENT
SHALL THE COPYRIGHT HOLDERS OR ANYONE DISTRIBUTING THE SOFTWARE BE LIABLE
FOR ANY DAMAGES OR OTHER LIABILITY, WHETHER IN CONTRACT, TORT OR OTHERWISE,
ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
DEALINGS IN THE SOFTWARE.
*/

/**
 * Provides classes and utilities for terrain rendering.
 *
 * Description:
 * The `dagon.graphics.terrain` module defines the `Terrain` class
 * for rendering procedural terrains, as well as `TerrainMaterial`
 * for managing terrain-specific material parameters and textures,
 * The module supports multi-layered materials with splat mapping.
 *
 * Copyright: Rafał Ziemniewski, Timur Gafarov 2018-2025
 * License: $(LINK2 https://boost.org/LICENSE_1_0.txt, Boost License 1.0).
 * Authors: Rafał Ziemniewski, Timur Gafarov
 */
module dagon.graphics.terrain;

import dlib.core.memory;
import dlib.core.ownership;
import dlib.container.array;
import dlib.math.vector;
import dlib.geometry.sphere;
import dlib.geometry.triangle;
import dlib.image.color;

import dagon.graphics.drawable;
import dagon.graphics.mesh;
import dagon.graphics.heightmap;
import dagon.graphics.entity;
import dagon.graphics.material;
import dagon.graphics.texture;

/**
 * Represents layered terrain material.
 *
 * Description:
 * The `TerrainMaterial` class manages splat maps, texture layers,
 * and blending parameters used for physically-based terrain shading.
 */
class TerrainMaterial: Material
{
    /// Array of terrain texturing layers, where each layer is a separate material
    Array!Material layers;
    
    /**
     * Constructs a new `TerrainMaterial` object.
     *
     * Params:
     *   owner = The owner object.
     */
    this(Owner owner)
    {
        super(owner);
        alphaTestThreshold = 0.0f;
    }
    
    /// Adds a new layer
    Material addLayer()
    {
        Material layerMaterial = New!Material(this);
        layerMaterial.alphaTestThreshold = alphaTestThreshold;
        layers.append(layerMaterial);
        return layerMaterial;
    }
    
    // TODO: remove layer
    
    /// Destructor. Releases all associated resources.
    ~this()
    {
        layers.free();
    }
}

/**
 * A terrain object.
 *
 * Description:
 * A `Terrain` is generated from an abstract `Heightmap`, which can be a height data
 * loaded from a grayscale image, or a procedurally generated 2D noise.
 * The terrain consists of a render mesh and a collision mesh, both generated at
 * configurable resolutions. The class supports normal generation, mesh refreshing,
 * and provides methods for height queries and spatial traversal.
 */
class Terrain: Owner, Drawable
{
    /// Horizontal resolution (number of vertices along X).
    uint width;

    /// Vertical resilution (number of vertices along Z).
    uint height;

    /// The underlying render mesh of the terrain.
    Mesh mesh;
    
    /// The underlying collision mesh the terrain.
    Mesh collisionMesh;

    /// The heightmap source.
    Heightmap heightmap;

    /**
     * Constructs a square terrain with specified mesh and collision mesh resolutions.
     *
     * Params:
     *   meshResolution          = Visual mesh vertex resolution.
     *   collisionMeshResolution = Collision mesh vertex resolution.
     *   heightmap               = The heightmap source.
     *   owner                   = The owner object.
     */
    this(uint meshResolution, uint collisionMeshResolution, Heightmap heightmap, Owner owner)
    {
        super(owner);

        this.width = meshResolution;
        this.height = meshResolution;
        this.heightmap = heightmap;

        mesh = generateMesh(width, height, 1, owner);
        mesh.dataReady = true;
        mesh.prepareVAO();

        float scale = cast(float)meshResolution / collisionMeshResolution;
        collisionMesh = generateMesh(collisionMeshResolution, collisionMeshResolution, scale, owner);
    }

    /**
     * Constructs a square terrain with default collision mesh resolution.
     *
     * Params:
     *   meshResolution = Visual mesh vertex resolution.
     *   heightmap      = The heightmap source.
     *   owner          = The owner object.
     */
    this(uint meshResolution, Heightmap heightmap, Owner owner)
    {
        this(meshResolution, 80, heightmap, owner);
    }

    /**
     * Generates a mesh from the heightmap.
     *
     * Params:
     *   w     = Width of a terrain in vertices.
     *   h     = Height of a terrain in vertices.
     *   scale = Scale multiplier 
     *   owner = The owner object.
     */
    Mesh generateMesh(uint w, uint h, float scale, Owner owner)
    {
        Mesh mesh = New!Mesh(owner);

        size_t numVerts = w * h;
        mesh.vertices = New!(Vector3f[])(numVerts);
        mesh.normals = New!(Vector3f[])(numVerts);
        mesh.texcoords = New!(Vector2f[])(numVerts);
        mesh.indices = New!(uint[3][])(numVerts * 2);

        int i = 0;
        foreach(x; 0..w)
        foreach(z; 0..h)
        {
            float y = heightmap.getHeight(
                cast(float)x / cast(float)(w-1),
                cast(float)z / cast(float)(h-1));
            mesh.vertices[i] = Vector3f(x * scale, y, z * scale);
            mesh.texcoords[i] = Vector2f(
                cast(float)x / cast(float)(w-1),
                cast(float)z / cast(float)(h-1));
            i += 1;
        }

        i = 0;
        foreach(x; 0..w-1)
        foreach(z; 0..h-1)
        {
            uint LU = x + z * w;
            uint RU = x+1 + z * w;
            uint LB = x + (z+1) * w;
            uint RB = x+1 + (z+1) * w;

            mesh.indices[i] = [LU, RU, RB];
            mesh.indices[i+1] = [LU, RB, LB];
            i += 2;
        }

        mesh.generateNormals();

        return mesh;
    }

    /// Updates the terrain (stub for future logic).
    void update(double dt)
    {

    }

    /// Renders the terrain mesh.
    void render(GraphicsState* state)
    {
        mesh.render(state);
    }

    /// Regenerates normals and VAO for the mesh.
    void refreshChanges()
    {
        mesh.generateNormals();
        mesh.prepareVAO();
    }

    /**
     * Returns the terrain height at a given world position.
     *
     * Params:
     *   entity = The entity representing the terrain.
     *   pos    = The world position to query.
     * Returns:
     *   The height value at the given position.
     */
    float getHeight(Entity entity, Vector3f pos)
    {
        Vector3f ts = (pos - entity.position) / entity.scaling;
        float x = ts.x / width;
        float z = ts.z / height;
        float y = heightmap.getHeight(x, z);
        return y * entity.scaling.y;
    }

    /**
     * Returns an aggregate for iterating terrain triangles that intersect a given sphere.
     *
     * Params:
     *   sphere = Pointer to the sphere to test against.
     * Returns:
     *   A `TerrainSphereTraverseAggregate` for triangle iteration.
     */
    TerrainSphereTraverseAggregate traverseBySphere(Sphere* sphere)
    {
        return TerrainSphereTraverseAggregate(this, sphere);
    }
}

/**
 * A sphere traversal aggregate.
 *
 * Description:
 * Represents data for iterating terrain triangles that intersect a given sphere.
 * It is meant to be used with `foreach` loop. The traversal is a simple brute-force
 * algorithm, so it can be not very efficient for detailed terrains.
 */
struct TerrainSphereTraverseAggregate
{
    Terrain terrain;
    Sphere* sphere;

    int opApply(int delegate(ref Triangle) dg)
    {
        int result = 0;

        uint x = 0;
        uint y = 0;

        Vector3f c = sphere.center;
        // TODO: transform c with position and scale?
        if (c.x > terrain.width - 1) x = terrain.width - 1;
        else if (c.x < 0) x = 0;
        else x = cast(uint)c.x;

        if (c.z > terrain.height - 1) y = terrain.height - 1;
        else if (c.z < 0) y = 0;
        else y = cast(uint)c.z;

        Triangle tri = terrain.mesh.getTriangle(y * terrain.width + x);
        tri.barycenter = (tri.v[0] + tri.v[1] + tri.v[2]) / 3;

        result = dg(tri);

        return result;
    }
}

/// Tests whether an entity holds a `Terrain`.
bool entityIsTerrain(Entity e)
{
    if (e.type == EntityType.Terrain)
        return true;
    
    Drawable d = e.drawable;
    if (d)
    {
        if (cast(Terrain)d)
            return true;
    }
    return false;
}
