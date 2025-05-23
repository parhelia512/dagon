/*
Copyright (c) 2020-2025 Timur Gafarov

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

module dagon.render.deferred.passes.forward;

import std.stdio;

import dlib.core.memory;
import dlib.core.ownership;
import dlib.image.color;

import dagon.core.bindings;
import dagon.graphics.entity;
import dagon.graphics.shader;
import dagon.graphics.terrain;
import dagon.graphics.particles;
import dagon.render.pipeline;
import dagon.render.pass;
import dagon.render.framebuffer;
import dagon.render.deferred.gbuffer;
import dagon.render.deferred.shaders.forward;

class PassForward: RenderPass
{
    ForwardShader forwardShader;
    Framebuffer outputBuffer;
    GBuffer gbuffer;
    GLuint framebuffer = 0;

    this(RenderPipeline pipeline, GBuffer gbuffer, EntityGroup group = null)
    {
        super(pipeline, group);
        forwardShader = New!ForwardShader(this);
        
        this.gbuffer = gbuffer;
    }
    
    void prepareFramebuffer()
    {
        if (framebuffer)
            return;
    
        glGenFramebuffers(1, &framebuffer);
        glBindFramebuffer(GL_FRAMEBUFFER, framebuffer);
        glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, outputBuffer.colorTexture, 0);
        glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT1, GL_TEXTURE_2D, gbuffer.velocityTexture, 0);
        glFramebufferTexture2D(GL_FRAMEBUFFER, GL_DEPTH_STENCIL_ATTACHMENT, GL_TEXTURE_2D, outputBuffer.depthTexture, 0);
        
        GLenum[2] drawBuffers = 
        [
            GL_COLOR_ATTACHMENT0, 
            GL_COLOR_ATTACHMENT1
        ];
        
        glDrawBuffers(drawBuffers.length, drawBuffers.ptr);

        GLenum status = glCheckFramebufferStatus(GL_FRAMEBUFFER);
        if (status != GL_FRAMEBUFFER_COMPLETE)
            writeln(status);

        glBindFramebuffer(GL_FRAMEBUFFER, 0);
    }
    
    void resize(uint w, uint h)
    {
        if (glIsFramebuffer(framebuffer))
        {
            glDeleteFramebuffers(1, &framebuffer);
            framebuffer = 0;
        }
    }

    override void render()
    {
        if (group && outputBuffer)
        {
            state.environment = pipeline.environment;
            
            prepareFramebuffer();
            
            bindFramebuffer(framebuffer);

            glBindFramebuffer(GL_READ_FRAMEBUFFER, gbuffer.framebuffer);
            glBlitFramebuffer(0, 0, gbuffer.width, gbuffer.height, 0, 0, gbuffer.width, gbuffer.height, GL_DEPTH_BUFFER_BIT, GL_NEAREST);
            glBindFramebuffer(GL_READ_FRAMEBUFFER, 0);

            glScissor(0, 0, outputBuffer.width, outputBuffer.height);
            glViewport(0, 0, outputBuffer.width, outputBuffer.height);
            
            glEnablei(GL_BLEND, 0);
            glEnablei(GL_BLEND, 1);
            glBlendFunci(0, GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);

            foreach(entity; group)
            {
                if (entity.visible)
                {
                    if (entity.drawable)
                    {
                        if (!entityIsTerrain(entity) && !entityIsParticleSystem(entity))
                        {
                            Shader shader = forwardShader;

                            if (entity.material)
                            {
                                if (entity.material.shader)
                                    shader = entity.material.shader;
                            }

                            shader.bind();
                            renderEntity(entity, shader);
                            shader.unbind();
                        }
                    }
                    
                    foreach(c; entity.components)
                    {
                        if (c.visible)
                        {
                            c.render(&state);
                        }
                    }
                }
            }

            glDisablei(GL_BLEND, 0);
            glDisablei(GL_BLEND, 1);
        }
    }
}
