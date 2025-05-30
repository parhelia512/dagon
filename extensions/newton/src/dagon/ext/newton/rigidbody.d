/*
Copyright (c) 2019-2025 Timur Gafarov

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

module dagon.ext.newton.rigidbody;

import dlib.core.ownership;
import dlib.core.memory;
import dlib.math.vector;
import dlib.math.matrix;
import dlib.math.quaternion;
import dlib.math.transformation;
import bindbc.newton;
import dagon.core.event;
import dagon.core.time;
import dagon.graphics.entity;
import dagon.ext.newton.world;
import dagon.ext.newton.shape;

extern(C)
{
    nothrow @nogc void newtonBodyForceCallback(
        const NewtonBody* nbody,
        dFloat timestep,
        int threadIndex)
    {
        NewtonRigidBody b = cast(NewtonRigidBody)NewtonBodyGetUserData(nbody);
        if (b)
        {
            Vector3f gravityForce = b.gravity * b.mass;
            NewtonBodyAddForce(nbody, gravityForce.arrayof.ptr);
            NewtonBodyAddForce(nbody, b.force.arrayof.ptr);
            NewtonBodyAddTorque(nbody, b.torque.arrayof.ptr);
            b.force = Vector3f(0.0f, 0.0f, 0.0f);
            b.torque = Vector3f(0.0f, 0.0f, 0.0f);
        }
    }
}

class NewtonRigidBody: Owner
{
    NewtonPhysicsWorld world;
    NewtonBody* newtonBody;
    int materialGroupId;
    bool dynamic = false;
    float mass;
    Vector3f gravity = Vector3f(0.0f, -9.8f, 0.0f);
    Vector3f force = Vector3f(0.0f, 0.0f, 0.0f);
    Vector3f torque = Vector3f(0.0f, 0.0f, 0.0f);
    Vector4f position = Vector4f(0.0f, 0.0f, 0.0f, 1.0f);
    Quaternionf rotation = Quaternionf.identity;
    Matrix4x4f transformation = Matrix4x4f.identity;
    bool enableRotation = true;
    bool raycastable = true;
    bool sensor = false;
    void delegate(NewtonRigidBody, NewtonRigidBody) sensorCallback;
    void delegate(NewtonRigidBody, NewtonRigidBody, const void*) contactCallback;

    bool isRaycastable()
    {
        return raycastable;
    }
    
    bool isSensor()
    {
        return sensor;
    }

    this(NewtonCollisionShape shape, float mass, NewtonPhysicsWorld world, Owner o)
    {
        super(o);

        this.world = world;

        newtonBody = NewtonCreateDynamicBody(world.newtonWorld, shape.newtonCollision, transformation.arrayof.ptr);
        NewtonBodySetUserData(newtonBody, cast(void*)this);
        this.groupId = world.defaultGroupId;
        this.mass = mass;
        NewtonBodySetMassProperties(newtonBody, mass, shape.newtonCollision);
        NewtonBodySetForceAndTorqueCallback(newtonBody, &newtonBodyForceCallback);
        
        sensorCallback = &defaultSensorCallback;
        contactCallback = &defaultContactCallback;
    }
    
    void defaultSensorCallback(NewtonRigidBody, NewtonRigidBody)
    {
    }
    
    void defaultContactCallback(NewtonRigidBody, NewtonRigidBody, const void*)
    {
    }
    
    void setCollisionShape(NewtonCollisionShape shape)
    {
        if (shape.newtonCollision)
            NewtonBodySetCollision(newtonBody, shape.newtonCollision);
    }

    void update(double dt)
    {
        NewtonBodyGetPosition(newtonBody, position.arrayof.ptr);
        NewtonBodyGetMatrix(newtonBody, transformation.arrayof.ptr);
        if (enableRotation)
        {
            rotation = Quaternionf.fromMatrix(transformation);
        }
        else
        {
            rotation = Quaternionf.identity;
            transformation = translationMatrix(position.xyz);
            NewtonBodySetMatrix(newtonBody, transformation.arrayof.ptr);
        }
        // TODO: enableTranslation
    }
    
    void groupId(int id) @property
    {
        NewtonBodySetMaterialGroupID(newtonBody, id);
        materialGroupId = id;
    }
    
    int groupId() @property
    {
        return materialGroupId;
    }
    
    Vector3f worldCenterOfMass() @property
    {
        Vector3f centerOfMass;
        NewtonBodyGetCentreOfMass(newtonBody, centerOfMass.arrayof.ptr);
        return position.xyz + rotation.rotate(centerOfMass);
    }
    
    void centerOfMass(Vector3f center) @property
    {
        NewtonBodySetCentreOfMass(newtonBody, center.arrayof.ptr);
    }
    
    void addForce(Vector3f f)
    {
        force += f;
    }
    
    void addForceAtPos(Vector3f f, Vector3f pos)
    {
        force += f;
        torque += cross(pos - worldCenterOfMass(), f);
    }

    void addTorque(Vector3f t)
    {
        torque += t;
    }

    NewtonJoint* createUpVectorConstraint(Vector3f up)
    {
        return NewtonConstraintCreateUpVector(world.newtonWorld, up.arrayof.ptr, newtonBody);
    }
    
    void setTransformation(Matrix4x4f m)
    {
        NewtonBodySetMatrix(newtonBody, m.arrayof.ptr);
    }

    void velocity(Vector3f v) @property
    {
        NewtonBodySetVelocity(newtonBody, v.arrayof.ptr);
    }

    Vector3f velocity() @property
    {
        Vector3f v;
        NewtonBodyGetVelocity(newtonBody, v.arrayof.ptr);
        return v;
    }
    
    Vector3f pointVelocity(Vector3f worldPoint)
    {
        Vector3f v;
        NewtonBodyGetPointVelocity(newtonBody, worldPoint.arrayof.ptr, v.arrayof.ptr);
        return v;
    }
    
    Vector3f localPointVelocity(Vector3f point)
    {
        Vector3f worldPoint = point * transformation;
        return pointVelocity(worldPoint);
    }
    
    void addImpulse(Vector3f deltaVelocity, Vector3f impulsePoint, double dt)
    {
        NewtonBodyAddImpulse(newtonBody, deltaVelocity.arrayof.ptr, impulsePoint.arrayof.ptr, dt);
    }
    
    void onSensorCollision(NewtonRigidBody otherBody)
    {
        sensorCallback(this, otherBody);
    }
    
    void onContact(NewtonRigidBody otherBody, const void* contact)
    {
        contactCallback(this, otherBody, contact);
    }
}

class NewtonBodyController: EntityComponent
{
    NewtonRigidBody rigidBody;
    Matrix4x4f prevTransformation;

    this(EventManager em, Entity e, NewtonRigidBody b)
    {
        super(em, e);
        rigidBody = b;

        Quaternionf rot = e.rotation;
        rigidBody.transformation =
            translationMatrix(e.position) *
            rot.toMatrix4x4;

        NewtonBodySetMatrix(rigidBody.newtonBody, rigidBody.transformation.arrayof.ptr);

        prevTransformation = Matrix4x4f.identity;
    }

    override void update(Time t)
    {
        rigidBody.update(t.delta);

        entity.prevTransformation = prevTransformation;

        entity.position = rigidBody.position.xyz;
        entity.transformation = rigidBody.transformation * scaleMatrix(entity.scaling);
        entity.invTransformation = entity.transformation.inverse;
        entity.rotation = rigidBody.rotation;

        entity.absoluteTransformation = entity.transformation;
        entity.invAbsoluteTransformation = entity.invTransformation;
        entity.prevAbsoluteTransformation = entity.prevTransformation;

        prevTransformation = entity.transformation;
    }
}

alias NewtonBodyComponent = NewtonBodyController;

NewtonBodyController makeStaticBody(Entity entity, NewtonPhysicsWorld world, NewtonCollisionShape collisionShape)
{
    auto rigidBody = world.createStaticBody(collisionShape);
    return New!NewtonBodyController(world.eventManager, entity, rigidBody);
}

NewtonBodyController makeDynamicBody(Entity entity, NewtonPhysicsWorld world, NewtonCollisionShape collisionShape, float mass)
{
    auto rigidBody = world.createDynamicBody(collisionShape, mass);
    return New!NewtonBodyController(world.eventManager, entity, rigidBody);
}
