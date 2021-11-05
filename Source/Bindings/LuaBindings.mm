//
//  LuaBindings.cpp
//  Craft
//
//  Created by John Millard on 17/06/2015.
//  Copyright (c) 2015 Two Lives Left. All rights reserved.
//

#include "LuaBindings.h"

// Core
#include "Scene.h"
#include "SafeEntity.h"

// Voxels
#include "Blockset.h"
#include "Chunk.h"
#include "noise.h"
#include "SafeBlockType.h"

// Vector Math
#include <glm/mat4x4.hpp>
#include <glm/vec2.hpp>
#include <glm/vec3.hpp>
#include <glm/vec4.hpp>
#include <glm/gtc/quaternion.hpp>
#include <glm/gtx/quaternion.hpp>
#include <glm/gtx/euler_angles.hpp>

#include <sstream>
#include <algorithm>

// Rendering
#include "Shader.hpp"
#include "Material.hpp"
#include "Texture.h"
#include "CubeTexture.hpp"
#include "Mesh.hpp"
#include "MeshTools.hpp"
#include "SafeChunk.h"
#include "ChunkSerializer.hpp"
#include "ScreenUtilities.hpp"
#include "BloomPostEffect.hpp"
#include "DepthOfFieldPostEffect.hpp"
#include "SelectionPostEffect.hpp"

#include "Camera.h"
#include "SafeCamera.h"
#include "SafeMeshRenderer.h"
#include "SafeTransform.h"
#include "SafeLight.hpp"
#include "DebugRenderer.h"

// Physics
#include "SafeBody.hpp"
#include "BoxCollider.h"
#include "SafeRigidbody.h"
#include "SafeBoxShape.h"
#include "SafeMeshShape.h"
#include "SafeSphereShape.h"
#include "SafeCapsuleShape.h"

// Misc
#include "Touch.h"
#include "LuaBehaviour.h"
#include "ScriptAsset.h"
#include "FileUtilities.h"
#include "EditorBridge.h"
#include "Random.hpp"

#include <json/json.h>

extern "C"
{
    #import <RuntimeKit/color.h>
}

#import <RuntimeKit/assets.h>

#define _def_float(f) _def<float, long((f) * 1000000), 1000000>

using namespace LuaIntf;

namespace CodeaCraft {
    static int submesh_index_from_1_based_index(CodeaCraft::MeshPtr mesh, int index) {
        int count = (int)mesh->getSubMeshCount();
        int clampedIndex = std::max(index - 1, 0);
        return std::min(clampedIndex, count - 1);
    }
}

namespace CodeaCraft
{
    static const char* kLuaErrorMsgMissingRigidbodyComponent = "Entity is missing required component: rigidbody";
    
    static const char *SafeComponentRegistryKey = "SafeComponentRegistryKey";
    
    void register_misc(LuaRef& module)
    {
        std::string originalPath = Lua::getGlobal<std::string>(module.state(), "package.path");
        
        Lua::setGlobal(module.state(), "package.path", FileUtilities::getBundlePath() + "/?.lua");
        
        try {
            LuaIntf::LuaRef luaClass = Lua::getGlobal(module.state(), "require").call<LuaIntf::LuaRef>("middleclass");
            module.set("mclass", luaClass);
        } catch (const std::exception& e) {
            NSLog(@"Failed to register middleclass module");
        }
                
        try {
            LuaIntf::LuaRef luaBlock = Lua::getGlobal(module.state(), "require").call<LuaIntf::LuaRef>("block");
            module.set("block", luaBlock);
        } catch (const std::exception& e) {
            NSLog(@"Failed to register block module");
        }
        
        Lua::setGlobal(module.state(), "package.path", originalPath);
    }

    // from http://answers.unity3d.com/questions/467614/what-is-the-source-code-of-quaternionlookrotation.html
    static glm::quat lookRotation(glm::vec3 forward, glm::vec3 up)
    {
        glm::vec3 vector = glm::normalize(forward);
        glm::vec3 vector2 = glm::normalize(glm::cross(up, vector));
        glm::vec3 vector3 = glm::cross(vector, vector2);
        float m00 = vector2.x;
        float m01 = vector2.y;
        float m02 = vector2.z;
        float m10 = vector3.x;
        float m11 = vector3.y;
        float m12 = vector3.z;
        float m20 = vector.x;
        float m21 = vector.y;
        float m22 = vector.z;
        
        
        float num8 = (m00 + m11) + m22;
        glm::quat quaternion;
        if (num8 > 0.f)
        {
            float num = std::sqrtf(num8 + 1.f);
            quaternion.w = num * 0.5f;
            num = 0.5f / num;
            quaternion.x = (m12 - m21) * num;
            quaternion.y = (m20 - m02) * num;
            quaternion.z = (m01 - m10) * num;
            return quaternion;
        }
        if ((m00 >= m11) && (m00 >= m22))
        {
            float num7 = std::sqrtf(((1.f + m00) - m11) - m22);
            float num4 = 0.5f / num7;
            quaternion.x = 0.5f * num7;
            quaternion.y = (m01 + m10) * num4;
            quaternion.z = (m02 + m20) * num4;
            quaternion.w = (m12 - m21) * num4;
            return quaternion;
        }
        if (m11 > m22)
        {
            float num6 = std::sqrtf(((1.f + m11) - m00) - m22);
            float num3 = 0.5f / num6;
            quaternion.x = (m10+ m01) * num3;
            quaternion.y = 0.5f * num6;
            quaternion.z = (m21 + m12) * num3;
            quaternion.w = (m20 - m02) * num3;
            return quaternion;
        }
        float num5 = std::sqrtf(((1.f + m22) - m00) - m11);
        float num2 = 0.5f / num5;
        quaternion.x = (m20 + m02) * num2;
        quaternion.y = (m21 + m12) * num2;
        quaternion.z = 0.5f * num5;
        quaternion.w = (m01 - m10) * num2;
        return quaternion;
    }
    
    int blockset_index(lua_State* L)
    {
        Blockset* blockset = Lua::get<Blockset*>(L, 1);
        const char* key = luaL_checkstring(L, 2);
        
        block_id id = BlockType::InvalidIndex;
        id = blockset->blockTypeIndex(key);
        
        if (id != BlockType::InvalidIndex)
        {
            LuaIntf::Lua::push(L, (*blockset)[id].luaClass);
            return 1;
        }
        
        return CppBindClassMetaMethod::index(L);
    }

    
    void register_blockset(LuaRef& module)
    {
        std::map<BlockFace, std::string> blockFaceToStringMap =
        {
            {BlockFace::East, "east"},
            {BlockFace::South, "south"},
            {BlockFace::West, "west"},
            {BlockFace::North, "north"},
            {BlockFace::Up, "up"},
            {BlockFace::Down, "down"},
        };
        
        LuaBinding(module)
        
        .beginClass<BlockState>("blockState")
        .addCustomFunction("addFlag", [] (BlockState* blockState, std::string name, bool defaultValue)
                           {
                               return blockState->addProperty(name, defaultValue) == BlockState::ModifyPropertyResult::PropertyModified;
                           })
        .addCustomFunction("addRange", [] (BlockState* blockState, std::string name, int minRange, int maxRange, int defaultValue)
                           {
                               return blockState->addProperty(name, minRange, maxRange, defaultValue) == BlockState::ModifyPropertyResult::PropertyModified;
                           })
        .addCustomFunction("addList", [] (BlockState* blockState, std::string name, std::vector<std::string> values, std::string defaultValue)
                           {
                               return blockState->addProperty(name, values, defaultValue) == BlockState::ModifyPropertyResult::PropertyModified;
                           })        
        .endClass()
        
        .beginClass<SafeBlockType>("BlockType")
        .addPropertyReadOnly("id", &SafeBlockType::blockID)
        .addPropertyReadOnly("name", &SafeBlockType::getName)
        .addPropertyReadOnly("state", &SafeBlockType::getState)
        .addPropertyReadOnly("model", &SafeBlockType::getModel)
        .addProperty("geometry", &SafeBlockType::getGeometry, &SafeBlockType::setGeometry)
        .addProperty("renderPass", &SafeBlockType::getRenderPass, &SafeBlockType::setRenderPass)
        .addProperty("tinted", &SafeBlockType::isTinted, &SafeBlockType::setTinted)
        .addProperty("dynamic", &SafeBlockType::isDynamic, &SafeBlockType::setDynamic)
        .addProperty("scripted", &SafeBlockType::isScripted, &SafeBlockType::setScripted)
        .addFunction("setTexture", &SafeBlockType::setTexture, LUA_ARGS(int, std::string))
        .addFunction("setColor", &SafeBlockType::lua_setColor)
        .endClass()
        
        .beginClass<BlockModel>("BlockModel")
        .addFunction("clear", &BlockModel::clearElements)
        .addFunction("rotateY", &BlockModel::rotateY)
        .addFunction("rotateX", &BlockModel::rotateX)
        .addCustomFunction("addElement", [blockFaceToStringMap] (lua_State* L)
        {
            int n = lua_gettop(L);
            if (n == 2)
            {
                BlockModel* model = LuaIntf::Lua::get<BlockModel*>(L, 1);
                LuaIntf::LuaRef table = LuaIntf::Lua::get(L, 2);
                
                if (model && table.isValid() && table.isTable())
                {
                    glm::vec3 lower = table.has("lower") ? table.get<glm::vec3>("lower") : glm::vec3(0,0,0);
                    glm::vec3 upper = table.has("upper") ? table.get<glm::vec3>("upper") : glm::vec3(255,255,255);
                    
                    bool overrideTextures = false;
                    std::string elementTexture;
                    if (table.has("textures"))
                    {
                        overrideTextures = true;
                        elementTexture = table.get<std::string>("textures");
                    }
                    
                    BlockElement element;
                    element.setLower(lower);
                    element.setUpper(upper);
                    for (int i = 0; i < BlockFace::Count; i++)
                    {
                        BlockFace face = (BlockFace)i;
                        
                        std::string faceName = blockFaceToStringMap.find(face)->second;
                        std::string faceTexture = overrideTextures ? elementTexture : ("$" + faceName);
                        
                        LuaRef faceTable = table.get<LuaRef>(faceName);

                        
                        if (faceTable.isValid() && faceTable.isTable())
                        {
                            if (faceTable.has("texture"))
                            {
                                faceTexture = faceTable.get<std::string>("texture");
                            }
                        }
                        
                        element.face(face).visible = true;
                        element.face(face).texture = faceTexture;
                        element.face(face).cullface = face;
                        element.face(face).color = "$" + faceName;
                        
                        glm::ivec3 normal = normalFromBlockFace(face);
                        int ui = 0, vi = 1;
                        
                        if (normal.x != 0)
                        {
                            ui = 2; // z
                            vi = 1; // y
                            if (normal.x == -1)
                            {
                                std::swap(lower.z, upper.z);
                            }
                        }
                        else if (normal.y != 0)
                        {
                            ui = 0; // x
                            vi = 2; // z
                        }
                        else if (normal.z != 0)
                        {
                            ui = 0; // x
                            vi = 1; // y
                            if (normal.z == -1)
                            {
                                std::swap(lower.x, upper.x);
                            }
                        }

                        element.face(face).uvPoint1 = glm::ivec2(lower[ui],lower[vi]);
                        element.face(face).uvPoint2 = glm::ivec2(upper[ui],upper[vi]);
                    }
                    model->addElement(element);
                }
            }
        })
        .endClass()
        
        .beginClass<Blockset>("blocks")
        .addFunction("blockID", &Blockset::blockTypeIndex, LUA_ARGS(std::string))
        .addFunction("get", &Blockset::lua_get)
        .addFunction("all", &Blockset::lua_blockTypes)
        .addFunction("new", &Blockset::lua_newBlock)
        .addFunction("addAssetPack", &Blockset::addAssetPack, LUA_ARGS(std::string))
        .addFunction("addAsset", &Blockset::addAsset, LUA_ARGS(std::string))
        .endClass();
        
        // Dig up the metatables for Material for some lua voodoo
        LuaRef registry(module.state(), LUA_REGISTRYINDEX);
        LuaRef mt = registry.rawget(LuaRef::fromPtr(module.state(), CppClassSignature<Blockset>::value()));
        
        mt.rawset("__index", blockset_index);
        mt.rawget("___const").rawset("__index", blockset_index);
    }
    
    int material_newindex(lua_State* L)
    {
        Material* material = Lua::get<Material*>(L, 1);
        const char* key = luaL_checkstring(L, 2);
        int8_t id = material->propertyID(key);
        if (material->isValidPropertyID(id))
        {
            return material->lua_setProperty(L);
        }
        
        return CppBindClassMetaMethod::newIndex(L);
    }
    
    int material_index(lua_State* L)
    {
        Material* material = Lua::get<Material*>(L, 1);
        const char* key = luaL_checkstring(L, 2);
        int8_t id = material->propertyID(key);
        if (material->isValidPropertyID(id))
        {
            return material->lua_getProperty(L);
        }
        
        return CppBindClassMetaMethod::index(L);
    }

    void register_material(LuaRef& module)
    {
        LuaBinding(module)
        .beginClass<Shader>("shader")
        .addStaticFunction("add", [] (LuaRef table)
        {
            ShaderPtr newShader = std::make_shared<Shader>( );
            newShader->loadFromLuaTable(table);
            RenderSystem::resources().addShader(newShader->name().c_str(), newShader);
        })
        .endClass();
        
        LuaBinding(module)
        .beginClass<Material>("material")
        .addFactory([] (lua_State* L) {
            NSString *nsPath = assetPathOnStackAtIndex(L, 2, AssetKeyStackOptionsMustExist | AssetKeyStackOptionsAllowLibraries);
                        
            bool async = Lua::opt<bool>(L, 3, false);
            
            MaterialPtr mat;
            if(nsPath) {
                mat = std::make_shared<Material>(nsPath.UTF8String, async);
            } else {
                mat = std::make_shared<Material>(luaL_checkstring(L, 2), async);
            }
            
            CppObjectSharedPtr<MaterialPtr, Material>::pushToStack(L, mat, false);
            
            return 1;
        })
        .addConstant("int", ShaderUniformType::Integer)
        .addConstant("float", ShaderUniformType::Float)
        .addConstant("bool", ShaderUniformType::Boolean)
        .addConstant("vec2", ShaderUniformType::Vec2)
        .addConstant("vec3", ShaderUniformType::Vec3)
        .addConstant("vec4", ShaderUniformType::Vec4)
        .addConstant("mat2", ShaderUniformType::Mat2)
        .addConstant("mat3", ShaderUniformType::Mat3)
        .addConstant("mat4", ShaderUniformType::Mat4)
        .addConstant("texture2D", ShaderUniformType::Texture2D)
        .addConstant("cubeTexture", ShaderUniformType::CubeTexture)
        .addConstant("unsupported", ShaderUniformType::Unsupported)
        .addConstant("skybox", RenderQueue::Skybox)
        .addConstant("solid", RenderQueue::Solid)
        .addConstant("transparent", RenderQueue::Transparent)
        .addFunction("addOption", &Material::addOption, LUA_ARGS(std::string, _opt<bool>, _opt<std::vector<std::string>>))
        .addFunction("setOption", &Material::setOption, LUA_ARGS(std::string, bool))
        .addFunction("addProperty", &Material::lua_addProperty)
        .addFunction("getProperty", &Material::lua_getProperty)
        .addFunction("setProperty", &Material::lua_setProperty)
        .addFunction("getProperties", &Material::lua_getProperties)
        .addFunction("hasProperty", &Material::hasProperty)
        .addProperty("blendMode", &Material::getBlendMode, &Material::setBlendMode)
        .addProperty("renderQueue", &Material::getRenderQueue, &Material::setRenderQueue)
        .addProperty("depthWrite", &Material::getDepthWrite, &Material::setDepthWrite)
        .addProperty("colorMask", &Material::getColorMask, &Material::setColorMask)
        .addProperty("order", &Material::getOrder, &Material::setOrder)
        .addPropertyReadOnly("waiting", &Material::isWaitingForCompile)
        .addStaticFunction("preset", [](lua_State* L)
        {
            NSString *nsPath = assetPathOnStackAtIndex(L, 1, AssetKeyStackOptionsMustExist | AssetKeyStackOptionsAllowLibraries);
            MaterialPtr material = Material::createFromPreset(nsPath.UTF8String);
            CppObjectSharedPtr<MaterialPtr, Material>::pushToStack(L, material, false);
            return 1;
        })
        .addCustomFunction("__tostring", [](MaterialPtr material)
                           {
                               std::ostringstream sstream;
                               sstream  << "material: (";
                               sstream  << material->getShaderPath() << ")";
                               return sstream.str();
                           })
        .endClass();
        
        {
            auto materialClass = LuaBinding(module).beginClass<Material>("material");

            using CppGetter = CppBindClassMethod<Material, int(Material::*)(lua_State*)>;
            using CppSetter = CppBindClassMethod<Material, int(Material::*)(lua_State*)>;
            
            materialClass.setMemberGetter("errors", LuaRef::createFunction(module.state(), &CppGetter::call, CppGetter::function(&Material::lua_getErrors)));
            
            // Dig up the metatables for Material for some lua voodoo
            LuaRef registry(module.state(), LUA_REGISTRYINDEX);
            LuaRef mt = registry.rawget(LuaRef::fromPtr(module.state(), CppClassSignature<Material>::value()));
            
            mt.rawset("__newindex", material_newindex);
            mt.rawset("__index", material_index);
            mt.rawget("___const").rawset("__newindex", material_newindex);
            mt.rawget("___const").rawset("__index", material_index);
        }
        
        LuaBinding(module)
        .beginClass<PostEffect>("postEffect")
        .endClass()
        
        .beginExtendClass<BloomPostEffect, PostEffect>("bloomEffect")
        .addConstructor(LUA_SP(BloomPostEffectPtr), LUA_ARGS())
        .addProperty("enabled", &BloomPostEffect::isEnabled, &BloomPostEffect::setEnabled)
        .addProperty("iterations", &BloomPostEffect::getIterations, &BloomPostEffect::setIterations)
        .addProperty("threshold", &BloomPostEffect::getThreshold, &BloomPostEffect::setThreshold)
        .addProperty("softThreshold", &BloomPostEffect::getSoftThreshold, &BloomPostEffect::setSoftThreshold)
        .addProperty("intensity", &BloomPostEffect::getIntensity, &BloomPostEffect::setIntensity)
        .endClass()

        .beginExtendClass<DepthOfFieldPostEffect, PostEffect>("depthOfFieldEffect")
        .addConstructor(LUA_SP(DepthOfFieldPtr), LUA_ARGS())
        .addProperty("enabled", &DepthOfFieldPostEffect::isEnabled, &DepthOfFieldPostEffect::setEnabled)
        .endClass()
        
        .beginExtendClass<SelectionPostEffect, PostEffect>("selectionEffect")
        .addConstructor(LUA_SP(SelectionPostEffectPtr), LUA_ARGS())
        .endClass();
        
        {
            auto selectionEffectClass = LuaBinding(module).beginClass<SelectionPostEffect>("selectionEffect");
            
            // Workaround to allow nil property setting. Directly set setter and getter function for SafeEntity parent property
            using CppGetter = CppBindClassMethod<SelectionPostEffect, int(SelectionPostEffect::*)(lua_State*)>;
            using CppSetter = CppBindClassMethod<SelectionPostEffect, int(SelectionPostEffect::*)(lua_State*)>;
            selectionEffectClass.setMemberGetter("selection", LuaRef::createFunction(module.state(), &CppGetter::call, CppGetter::function(&SelectionPostEffect::lua_getSelection)));
            selectionEffectClass.setMemberSetter("selection", LuaRef::createFunction(module.state(), &CppSetter::call, CppSetter::function(&SelectionPostEffect::lua_setSelection)));
        }

        
        
        LuaBinding(module)
        .beginClass<Texture>("texture")
        .addFactory([](lua_State* L)
                    {
                        int n = lua_gettop(L);
                        
                        TexturePtr texture = nullptr;
                        
                        // Texture(assetPath | systemPath)
                        // Texture(codeaImage)
                        if (n >= 2)
                        {
                            if (lua_isstring(L, 2))
                            {
                                std::string path = Lua::get<std::string>(L, 2);
                                if (path == "CAMERA")
                                {
                                    texture = Texture::wrapCodeaCamera(L, 2);
                                }
                                else if (path == "CAMERA_DEPTH")
                                {
                                    texture = Texture::wrapCodeaCameraDepth(L, 2);
                                }
                                else
                                {
                                    texture = std::make_shared<Texture>();
                                    
                                    if (texture->loadFromFile(path) == false)
                                    {
                                        return 0;
                                    }
                                }
                            }
                            else if (Texture::isCodeaImage(L, 2))
                            {
                                texture = Texture::wrapCodeaImage(L, 2);
                            }
                            else if (lua_isuserdata(L, 2))
                            {
                                std::string path = assetPathOnStackAtIndex(L, 2, AssetKeyStackOptionsMustExist).UTF8String;
                                texture = std::make_shared<Texture>();
                                
                                if (texture->loadFromFile(path) == false)
                                {
                                    return 0;
                                }
                            }
                            else
                            {
                                luaL_argerror(L, 2, "Expected asset key, string, or image");
                            }
                        }
//                        else if (n == 3)
//                        {
//                            // TODO: Texture(width, height, <format>)
//                            return 0;
//                        }
                        
                        if (texture.get())
                        {
                            LuaIntf::CppObjectSharedPtr<std::shared_ptr<Texture>, Texture>::pushToStack(L, texture, false);
                            return 1;
                        }
                        
                        return 0;
                    })
        .addFunction("generateMipmaps", &Texture::generateMipmaps)
        .addPropertyReadOnly("width", &Texture::getWidth)
        .addPropertyReadOnly("height", &Texture::getHeight)
        .addProperty("smooth", &Texture::isSmooth, &Texture::setSmooth)
        .addProperty("repeats", &Texture::getRepeat, &Texture::setRepeat)
        .addProperty("clamps", &Texture::getClamp, &Texture::setClamp)
        .addProperty("mirrors", &Texture::getMirror, &Texture::setMirror)
        .addProperty("maxAnisotropy", &Texture::getMaxAnisotropy, &Texture::setMaxAnisotropy)
        .addCustomFunction("__tostring", [](TexturePtr texture)
                           {
                               std::ostringstream sstream;
                               sstream  << "texture: (";
                               sstream  << texture->getWidth() << ", " << texture->getHeight() << ")";
                               return sstream.str();
                           })
        .endClass()
        .beginClass<CubeTexture>("cubeTexture")        
        .addFactory([] (lua_State* L)
        {
            LuaRef table = LuaRef(L, 2);
            
            if (table.isTable())
            {
                //TODO: AssetKey handle an array of asset keys...
                LuaRef firstArg = table[1];
                if (firstArg.type() == LuaTypeID::STRING)
                {
                    std::vector<std::string> files = table.toValue<std::vector<std::string>>();
                    CubeTexturePtr cubeTexture = CubeTexturePtr(new CubeTexture());
                    cubeTexture->loadFromFiles(files);
                    Lua::push(L, cubeTexture);
                    return 1;
                }
                else if (firstArg.type() == LuaTypeID::USERDATA)
                {
                    CubeTexturePtr cubeTexture = CubeTexture::constructFromCodeaImages(L, 2);
                    Lua::push(L, cubeTexture);
                    return 1;
                }
            }
            else if (table.type() == LuaTypeID::STRING || table.type() == LuaTypeID::USERDATA)
            {
                CubeTexturePtr cubeTexture = CubeTexture::constructFromAssetOrImage(L, 2);
                Lua::push(L, cubeTexture);
                return 1;
            }
            else if (table.type() == LuaTypeID::NUMBER)
            {
                CubeTexturePtr cubeTexture = CubeTexturePtr(new CubeTexture());
                cubeTexture->newWithResolution(table.toValue<int>(), lua_toboolean(L, 3));
                Lua::push(L, cubeTexture);
                return 1;
            }
            
            return 0;
        })
        .addFunction("generateMipmaps", &CubeTexture::generateMipmaps)
        .addCustomFunction("generateIrradiance", [](CubeTexturePtr cubeTexture, lua_State* L)
        {
            int n = lua_gettop(L);
            if (n >= 2)
            {
                CubeTexturePtr target = Lua::get<CubeTexturePtr>(L, 2);
                uint32_t samples = Lua::opt(L, 3, 1024u);
                return CubeTexture::generatePrefilteredIrradiance(cubeTexture, target, samples);
            }
            else
            {
                uint32_t samples = Lua::opt(L, 3, 1024u);
                return CubeTexture::generatePrefilteredIrradiance(cubeTexture, CubeTexturePtr(), samples);
            }
        })
        .addPropertyReadOnly("width", &CubeTexture::getWidth)
        .addPropertyReadOnly("height", &CubeTexture::getHeight)
        .addCustomFunction("__tostring", [](CubeTexturePtr cubeTexture)
                           {
                                std::ostringstream sstream;
                                sstream  << "cubeTexture: (";
                                sstream  << cubeTexture->getWidth() << ")";
                                return sstream.str();
                           })
        .endClass();
    }
    
    void register_mesh(LuaRef& module)
    {
        LuaBinding(module)
        
        .beginClass<Mesh>("model")
        .addFactory([] (lua_State* L)
                    {
                        if (lua_gettop(L) >= 2)
                        {
                            const char* assetPath = assetPathOnStackAtIndex(L, 2, AssetKeyStackOptionsMustExist).UTF8String;
                            if (assetPath == nullptr) return 0;
                            
                            uint8_t subdivisions = (uint8_t)Lua::opt(L, 3, 0);
                            
                            MeshPtr mesh = MeshTools::loadModel(assetPath, subdivisions);
                            Lua::push(L, mesh);
                            return 1;
                        }
                        else
                        {
                            MeshPtr mesh = std::make_shared<Mesh>();
                            Lua::push(L, mesh);
                            return 1;
                        }
                    })
        .addStaticFunction("cube", [] (lua_State* L)
                           {
                               glm::vec3 size(1,1,1);
                               glm::vec3 offset(0,0,0);
                               
                               if (lua_gettop(L) > 0)
                               {
                                   size = Lua::get<glm::vec3>(L, 1);
                               }
                               if (lua_gettop(L) > 1)
                               {
                                   offset = Lua::get<glm::vec3>(L, 2);
                               }
                               
                               MeshPtr newCube = MeshTools::cube(size, offset);
                               Lua::push(L, newCube);
                               return 1;
                           })
        .addStaticFunction("plane", [] (lua_State* L)
                           {
                               glm::vec2 size = Lua::get<glm::vec2>(L, 1);
                               glm::vec3 offset;
                               
                               if (lua_gettop(L) == 2)
                               {
                                   offset = Lua::get<glm::vec3>(L, 2);
                               }
                               
                               MeshPtr newPlane = MeshTools::plane(size, offset);
                               Lua::push(L, newPlane);
                               return 1;
                           })
        .addStaticFunction("icosphere", [] (lua_State* L)
                           {
                               int n = lua_gettop(L);
                               
                               float radius = n >= 1 ? Lua::get<float>(L,1) : 1.0f;
                               int recursionLevel = n >= 2 ? Lua::get<int>(L,2) : 1;
                               bool faceted = n >= 3 ? Lua::get<bool>(L,3) : false;
                               
                               MeshPtr newIcosphere = MeshTools::icosphere(radius, recursionLevel, faceted);
                               Lua::push(L, newIcosphere);
                               return 1;
                           })
        .addProperty("bounds", &Mesh::getBounds, &Mesh::setBounds)
        .addPropertyReadOnly("indexCount", &Mesh::indexCount)
        .addPropertyReadOnly("vertexCount", &Mesh::vertexCount)
        .addPropertyReadOnly("valid", &Mesh::isValid)
        .addCustomFunction("resize", [] (MeshPtr mesh, unsigned int size, int index = 1) {
            mesh->resizeVertices(size, submesh_index_from_1_based_index(mesh, index));
        }, LUA_ARGS(MeshPtr, unsigned int, _def<int, 1>))
        .addCustomFunction("resizeVertices", [] (MeshPtr mesh, unsigned int size, int index = 1) {
            mesh->resizeVertices(size, submesh_index_from_1_based_index(mesh, index));
        }, LUA_ARGS(MeshPtr, unsigned int, _def<int, 1>))
        .addCustomFunction("resizeIndices", [] (MeshPtr mesh, unsigned int size, int index = 1) {
            mesh->resizeIndices(size, submesh_index_from_1_based_index(mesh, index));
        }, LUA_ARGS(MeshPtr, unsigned int, _def<int, 1>))
        .addFunction("clear", &Mesh::clear)
        .addPropertyReadOnly("submeshCount", &Mesh::getSubMeshCount)
        .addCustomFunction("getMaterial", [] (MeshPtr mesh, int index = 1) {
            return mesh->getMaterial(submesh_index_from_1_based_index(mesh, index));
        }, LUA_ARGS(MeshPtr, _def<int, 1>))
        .addCustomFunction("setMaterial", [] (MeshPtr mesh, MaterialPtr material, int index = 1) {
            mesh->setMaterial(material, submesh_index_from_1_based_index(mesh, index));
        }, LUA_ARGS(MeshPtr, MaterialPtr, _def<int, 1>))
        .addFunction("position", &Mesh::lua_position)
        .addFunction("normal", &Mesh::lua_normal)
        .addFunction("uv", &Mesh::lua_uv)
        .addFunction("color", &Mesh::lua_color)
        .addFunction("index", &Mesh::lua_index)
        .addFunction("addElement", &Mesh::lua_addElement)
        .addCustomFunction("split", [] (MeshPtr mesh, int index = 1) {
            MeshTools::split(mesh->getSubMesh(submesh_index_from_1_based_index(mesh, index)));
        }, LUA_ARGS(MeshPtr, _def<int, 1>))
        .addCustomFunction("__tostring", [] ()
                           {
                               return "model";
                           })
        .endClass();
        
        // Custom Mesh Setters / Getters
        {
            auto meshClass = LuaBinding(module).beginClass<Mesh>("model");
            
            using CppGetter = CppBindClassMethod<Mesh, int(Mesh::*)(lua_State*)>;
            using CppSetter = CppBindClassMethod<Mesh, int(Mesh::*)(lua_State*)>;
            
            meshClass.setMemberGetter("positions", LuaRef::createFunction(module.state(), &CppGetter::call, CppGetter::function(&Mesh::lua_getPositions)));
            meshClass.setMemberSetter("positions", LuaRef::createFunction(module.state(), &CppSetter::call, CppSetter::function(&Mesh::lua_setPositions)));

            meshClass.setMemberGetter("normals", LuaRef::createFunction(module.state(), &CppGetter::call, CppGetter::function(&Mesh::lua_getNormals)));
            meshClass.setMemberSetter("normals", LuaRef::createFunction(module.state(), &CppSetter::call, CppSetter::function(&Mesh::lua_setNormals)));

            meshClass.setMemberGetter("colors", LuaRef::createFunction(module.state(), &CppGetter::call, CppGetter::function(&Mesh::lua_getColors)));
            meshClass.setMemberSetter("colors", LuaRef::createFunction(module.state(), &CppSetter::call, CppSetter::function(&Mesh::lua_setColors)));

            meshClass.setMemberGetter("uvs", LuaRef::createFunction(module.state(), &CppGetter::call, CppGetter::function(&Mesh::lua_getUvs)));
            meshClass.setMemberSetter("uvs", LuaRef::createFunction(module.state(), &CppSetter::call, CppSetter::function(&Mesh::lua_setUvs)));

            meshClass.setMemberGetter("indices", LuaRef::createFunction(module.state(), &CppGetter::call, CppGetter::function(&Mesh::lua_getIndices)));
            meshClass.setMemberSetter("indices", LuaRef::createFunction(module.state(), &CppSetter::call, CppSetter::function(&Mesh::lua_setIndices)));            
        }

        
        LuaBinding(module)
        .beginExtendClass<SafeMeshRenderer, SafeComponentBase>("renderer")
        .addProperty("material", &SafeMeshRenderer::getMaterial, &SafeMeshRenderer::setMaterial)
        .addProperty("model", &SafeMeshRenderer::getMesh, &SafeMeshRenderer::setMesh)
        .addProperty("mask", &SafeMeshRenderer::getMask, &SafeMeshRenderer::setMask)
        .addProperty("instances", &SafeMeshRenderer::getInstances, &SafeMeshRenderer::setInstances)
        .addFunction("getMaterial", &SafeMeshRenderer::getMaterialAtIndex, LUA_ARGS(_opt<int>))
        .addFunction("setMaterial", &SafeMeshRenderer::setMaterialAtIndex, LUA_ARGS(MaterialPtr, _opt<int>))

        .addCustomFunction("__tostring", [] ()
                           {
                               return "renderer";
                           })
        .endClass();
        
        // Custom Mesh Setters / Getters
        {
            auto meshRendererClass = LuaBinding(module).beginClass<SafeMeshRenderer>("renderer");
            
            using CppGetter = CppBindClassMethod<SafeMeshRenderer, int(SafeMeshRenderer::*)(lua_State*)>;
            using CppSetter = CppBindClassMethod<SafeMeshRenderer, int(SafeMeshRenderer::*)(lua_State*)>;
            
            meshRendererClass.setMemberGetter("materials", LuaRef::createFunction(module.state(), &CppGetter::call, CppGetter::function(&SafeMeshRenderer::lua_getMaterials)));
            meshRendererClass.setMemberSetter("materials", LuaRef::createFunction(module.state(), &CppSetter::call, CppSetter::function(&SafeMeshRenderer::lua_setMaterials)));
        }
        
        getSafeComponentRegistry(module.state())->registerSafeComponent<MeshRenderer, Renderer, SafeMeshRenderer>(module.get("renderer"), [] (lua_State* L, anax::Entity entity)
        {
            if (!entity.hasComponent<Renderer>())
            {
                // entity:add(craft.renderer)
                if (lua_gettop(L) == 2)
                {
                    entity.addComponent<MeshRenderer, Renderer>();
                }
                // entity:add(craft.renderer, mesh)
                else if (lua_gettop(L) == 3)
                {
                    MeshPtr mesh = Lua::get<MeshPtr>(L, 3);
                    entity.addComponent<MeshRenderer, Renderer>(mesh);
                }
                Lua::push(L, SafeMeshRenderer(entity));
                return 1;
            }
            return 0;
        });

        
        LuaBinding(module)
        .beginExtendClass<SafeLight, SafeComponentBase>("light")
        .addProperty("type", &SafeLight::getType, &SafeLight::setType)
        .addProperty("color", &SafeLight::getColor, &SafeLight::setColor)
        .addProperty("intensity", &SafeLight::getIntensity, &SafeLight::setIntensity)
        .addProperty("distance", &SafeLight::getDistance, &SafeLight::setDistance)
        .addProperty("angle", &SafeLight::getAngle, &SafeLight::setAngle)
        .addProperty("penumbra", &SafeLight::getPenumbra, &SafeLight::setPenumbra)
        .addProperty("decay", &SafeLight::getDecay, &SafeLight::setDecay)
        .addProperty("mask", &SafeLight::getMask, &SafeLight::setMask)
        .addCustomFunction("__tostring", [] ()
                           {
                               return "light";
                           })
        .endClass();
        
        getSafeComponentRegistry(module.state())->registerSafeComponent<Light, Light, SafeLight>(module.get("light"), [] (lua_State* L, anax::Entity entity)
        {
            if (!entity.hasComponent<Light>())
            {
                // entity:add(MeshRenderer)
                if (lua_gettop(L) == 2)
                {
                    entity.addComponent<Light>(Light::Type::Directional);
                }
                // entity:add(MeshRenderer, mesh)
                else if (lua_gettop(L) == 3)
                {
                    Light::Type lightType = Lua::get<Light::Type>(L, 3);
                    entity.addComponent<Light>(lightType);
                }
                Lua::push(L, SafeLight(entity));
                return 1;
            }
            return 0;
        });

    }
    
    void register_physics(LuaRef& module)
    {
        // These are defined by Codea as well
//        module.set("DYNAMIC", Rigidbody::Type::Dynamic);
//        module.set("STATIC", Rigidbody::Type::Static);
//        module.set("KINEMATIC", Rigidbody::Type::Kinematic);
        
        
        LuaBinding(module)
        
        .beginClass<BulletPhysicsSystem>("physics")
        .addProperty("gravity", &BulletPhysicsSystem::getGravity, &BulletPhysicsSystem::setGravity)
        .addProperty("paused", &BulletPhysicsSystem::isPaused, &BulletPhysicsSystem::setPaused)
        .addFunction("raycast", &BulletPhysicsSystem::lua_raycast)
        .addFunction("spherecast", &BulletPhysicsSystem::lua_sphereCast)
        .addFunction("sphereCast", &BulletPhysicsSystem::lua_sphereCast) // TODO: deprecate
        .addCustomFunction("__tostring", [] (Scene* scene)
                           {
                               return "physics";
                           })
        .endClass()
        
        .beginExtendClass<SafeRigidbody, SafeComponentBase>("rigidbody")
        // Properties
        .addProperty("type", &SafeRigidbody::getType, &SafeRigidbody::setType)
        .addProperty("group", &SafeRigidbody::getGroup, &SafeRigidbody::setGroup)
        .addProperty("mask", &SafeRigidbody::getMask, &SafeRigidbody::setMask)
        .addPropertyReadOnly("centerOfMass", &SafeRigidbody::getCenterOfMass)
        .addProperty("angularVelocity", &SafeRigidbody::getAngularVelocity, &SafeRigidbody::setAngularVelocity)
        .addProperty("linearVelocity", &SafeRigidbody::getLinearVelocity, &SafeRigidbody::setLinearVelocity)
        .addProperty("angularFactor", &SafeRigidbody::getAngularFactor, &SafeRigidbody::setAngularFactor)
        .addProperty("linearFactor", &SafeRigidbody::getLinearFactor, &SafeRigidbody::setLinearFactor)
        .addProperty("awake", &SafeRigidbody::isAwake, &SafeRigidbody::setAwake)
        .addProperty("sleepingAllowed", &SafeRigidbody::isSleepingAllowed, &SafeRigidbody::setSleepingAllowed)
        .addProperty("linearDamping", &SafeRigidbody::getLinearDamping, &SafeRigidbody::setLinearDamping)
        .addProperty("angularDamping", &SafeRigidbody::getAngularDamping, &SafeRigidbody::setAngularDamping)
        .addProperty("friction", &SafeRigidbody::getFriction, &SafeRigidbody::setFriction)
        .addProperty("rollingFriction", &SafeRigidbody::getRollingFriction, &SafeRigidbody::setRollingFriction)
        .addProperty("restitution", &SafeRigidbody::getRestitution, &SafeRigidbody::setRestitution)
        //Members
        .addFunction("applyForce", &SafeRigidbody::lua_applyForce)
        .addFunction("applyImpulse", &SafeRigidbody::applyImpulse, LUA_ARGS(glm::vec3, glm::vec3))
        .addFunction("applyTorque", &SafeRigidbody::applyTorque, LUA_ARGS(glm::vec3))
        .addFunction("applyTorqueImpulse", &SafeRigidbody::applyTorqueImpulse, LUA_ARGS(glm::vec3))
        .addCustomFunction("__tostring", [] ()
                           {
                               return "rigidbody";
                           })
        .endClass()

        .beginModule("shape")
        
            .beginExtendClass<SafeBoxShape, SafeComponentBase>("box")
            .addProperty("size", &SafeBoxShape::getSize, &SafeBoxShape::setSize)
            .addProperty("offset", &SafeBoxShape::getOffset, &SafeBoxShape::setOffset)        
            .addCustomFunction("__tostring", [] ()
                               {
                                   return "shape.box";
                               })
            .endClass()
            
            .beginExtendClass<SafeMeshShape, SafeComponentBase>("model")
            // TODO: bindings
            .addCustomFunction("__tostring", [] ()
                               {
                                   return "shape.model";
                               })
            .endClass()

            .beginExtendClass<SafeSphereShape, SafeComponentBase>("sphere")
            // TODO: bindings
            .addCustomFunction("__tostring", [] ()
                               {
                                   return "shape.sphere";
                               })
            .endClass()

            .beginExtendClass<SafeCapsuleShape, SafeComponentBase>("capsule")
            // TODO: bindings
            .addCustomFunction("__tostring", [] ()
                               {
                                   return "shape.capsule";
                               })
            .endClass()
        
        .endModule();
        
        getSafeComponentRegistry(module.state())->registerSafeComponent<Rigidbody, Rigidbody, SafeRigidbody>(module.get("rigidbody"), [] (lua_State* L, anax::Entity entity)
        {
            if (!entity.hasComponent<Rigidbody>())
            {
                int n = lua_gettop(L);
                
                Rigidbody::Type type = (n >= 3) ? (Rigidbody::Type)Lua::get<int>(L, 3) : Rigidbody::Type::Dynamic;
                float mass = (n >= 4) ? Lua::get<float>(L, 4) : 1.0f;
                
                entity.addComponent<Rigidbody>(type, mass);

                Lua::push(L, SafeRigidbody(entity));
                return 1;
            }
            return 0;
        });

        getSafeComponentRegistry(module.state())->registerSafeComponent<BoxShape, PhysicsShape, SafeBoxShape>(module.get("shape").get("box"), [=] (lua_State* L, anax::Entity entity)
        {
            if (!entity.hasComponent<Rigidbody>())
            {
                luaL_argerror(L, 2, kLuaErrorMsgMissingRigidbodyComponent);
            }
            
            if (!entity.hasComponent<PhysicsShape>())
            {
                int n = lua_gettop(L);
                
                glm::vec3 size = (n >= 3) ? Lua::get<glm::vec3>(L, 3) : glm::vec3(1,1,1);
                glm::vec3 offset = (n >= 4) ? Lua::get<glm::vec3>(L, 4) : glm::vec3(0,0,0);
                
                entity.addComponent<BoxShape, PhysicsShape>(size, offset);

                Lua::push(L, SafeBoxShape(entity));
                return 1;
            }
            return 0;
        });

        getSafeComponentRegistry(module.state())->registerSafeComponent<MeshShape, PhysicsShape, SafeBoxShape>(module.get("shape").get("model"), [=] (lua_State* L, anax::Entity entity)
        {
            if (!entity.hasComponent<Rigidbody>())
            {
                luaL_argerror(L, 2, kLuaErrorMsgMissingRigidbodyComponent);
            }
            
            if (!entity.hasComponent<PhysicsShape>())
            {
                int n = lua_gettop(L);

                // entity:add(MeshShape)
                if (n == 2)
                {
                    entity.addComponent<MeshShape, PhysicsShape>();
                }
                // entity:add(MeshShape, mesh)
                else if (n == 3)
                {
                    MeshPtr mesh = Lua::get<MeshPtr>(L, 3);
                    entity.addComponent<MeshShape, PhysicsShape>(mesh);
                }
                
                Lua::push(L, SafeMeshShape(entity));
                return 1;
            }
            return 0;
        });

        getSafeComponentRegistry(module.state())->registerSafeComponent<SphereShape, PhysicsShape, SafeSphereShape>(module.get("shape").get("sphere"), [=] (lua_State* L, anax::Entity entity)
        {
            if (!entity.hasComponent<Rigidbody>())
            {
                luaL_argerror(L, 2, kLuaErrorMsgMissingRigidbodyComponent);
            }
            
            if (!entity.hasComponent<PhysicsShape>())
            {
                int n = lua_gettop(L);
                float radius = n >= 3 ? Lua::get<float>(L, 3) : 1.0f;
                entity.addComponent<SphereShape, PhysicsShape>(radius);
                Lua::push(L, SafeSphereShape(entity));
                return 1;
            }
            return 0;
        });

        getSafeComponentRegistry(module.state())->registerSafeComponent<CapsuleShape, PhysicsShape, SafeCapsuleShape>(module.get("shape").get("capsule"), [=] (lua_State* L, anax::Entity entity)
        {
            if (!entity.hasComponent<Rigidbody>())
            {
                luaL_argerror(L, 2, kLuaErrorMsgMissingRigidbodyComponent);
            }
            
            if (!entity.hasComponent<PhysicsShape>())
            {
                int n = lua_gettop(L);
                float radius = n >= 3 ? Lua::get<float>(L, 3) : 0.5f;
                float height = n >= 4 ? Lua::get<float>(L, 4) : 2.0f;
                entity.addComponent<CapsuleShape, PhysicsShape>(radius, height);
                Lua::push(L, SafeCapsuleShape(entity));
                return 1;
            }
            return 0;
        });

        
    }

    void register_world(LuaRef& module)
    {
        LuaBinding(module)
        
        .beginClass<SafeTransform>("transform")
        .addProperty("parent", &SafeTransform::getParent, &SafeTransform::setParent)
        .addProperty("position",
                     &SafeTransform::getter<glm::vec3, &Transform::getPosition>,
                     &SafeTransform::setter<glm::vec3, &Transform::setPosition>)
        .addProperty("x",
                     &SafeTransform::getter<float, &Transform::getX>,
                     &SafeTransform::setter<float, &Transform::setX>)
        .addProperty("y",
                     &SafeTransform::getter<float, &Transform::getY>,
                     &SafeTransform::setter<float, &Transform::setY>)
        .addProperty("z",
                     &SafeTransform::getter<float, &Transform::getZ>,
                     &SafeTransform::setter<float, &Transform::setZ>)        
        .addProperty("rotation",
                     &SafeTransform::getter<glm::quat, &Transform::getRotation>,
                     &SafeTransform::setter<glm::quat, &Transform::setRotation>)
        .addProperty("scale",
                     &SafeTransform::getter<glm::vec3, &Transform::getScale>,
                     &SafeTransform::setter<glm::vec3, &Transform::setScale>)
        
        .addPropertyReadOnly("forward",
                             &SafeTransform::getter<glm::vec3, &Transform::forward>)
        .addPropertyReadOnly("right",
                             &SafeTransform::getter<glm::vec3, &Transform::right>)
        .addPropertyReadOnly("up",
                             &SafeTransform::getter<glm::vec3, &Transform::up>)
        .addPropertyReadOnly("worldPosition",
                             &SafeTransform::getter<glm::vec3, &Transform::getWorldPosition>)
        .addPropertyReadOnly("worldRotation",
                             &SafeTransform::getter<glm::quat, &Transform::getWorldRotation>)
        .endClass()
        
        // Renderering
        .beginExtendClass<SafeCamera, SafeComponentBase>("camera")
        .addFunction("screenToWorld", &SafeCamera::screenToWorld, LUA_ARGS(glm::vec3))
        .addFunction("screenToRay", &SafeCamera::screenToRay, LUA_ARGS(glm::vec2))
        .addFunction("worldToScreen", &SafeCamera::worldToScreen, LUA_ARGS(glm::vec3))
        .addProperty("ortho", &SafeCamera::isOrtho, &SafeCamera::setOrtho)
        .addProperty("orthoSize", &SafeCamera::getOrthoSize, &SafeCamera::setOrthoSize)
        .addProperty("clearColor", &SafeCamera::getClearColor, &SafeCamera::setClearColor)
        .addProperty("clearDepthEnabled", &SafeCamera::getClearDepthEnabled, &SafeCamera::setClearDepthEnabled)
        .addProperty("clearColorEnabled", &SafeCamera::getClearColorEnabled, &SafeCamera::setClearColorEnabled)
        .addProperty("depthTextureEnabled", &SafeCamera::isDepthTextureEnabled, &SafeCamera::setDepthTextureEnabled)
        .addProperty("colorTextureEnabled", &SafeCamera::isColorTextureEnabled, &SafeCamera::setColorTextureEnabled)
        .addProperty("selectionBufferEnabled", &SafeCamera::isSelectionBufferEnabled, &SafeCamera::setSelectionBufferEnabled)
        .addProperty("fieldOfView", &SafeCamera::getFieldOfView, &SafeCamera::setFieldOfView)
        .addProperty("nearPlane", &SafeCamera::getNearPlane, &SafeCamera::setNearPlane)
        .addProperty("farPlane", &SafeCamera::getFarPlane, &SafeCamera::setFarPlane)
        .addProperty("mask", &SafeCamera::getMask, &SafeCamera::setMask)
        .addProperty("hdr", &SafeCamera::isHDR, &SafeCamera::setHDR)
        .addProperty("exposure", &SafeCamera::getExposure, &SafeCamera::setExposure)
        .addProperty("tonemapping", &SafeCamera::getTonemapping, &SafeCamera::setTonemapping)
        .addProperty("logDepth", &SafeCamera::getLogDepth, &SafeCamera::setLogDepth)
        .addFunction("viewport", &SafeCamera::lua_viewport)
        .addFunction("addPostEffect", &SafeCamera::lua_addPostEffect)
        .addFunction("pick", &SafeCamera::lua_pick)
        .addCustomFunction("draw", [] (lua_State* L)
                           {
                                SafeCamera camera = Lua::get<SafeCamera>(L, 1);
            
                                RenderTarget* target = nullptr;
                                if (lua_gettop(L) >= 2)
                                {
                                    target = Lua::get<RenderTarget*>(L, 2);
                                }
                                uint32_t cubeFace = (uint32_t)luaL_optinteger(L, 3, 0) - 1;
            
                                Scene* scene = dynamic_cast<Scene*>(static_cast<BaseWorld*>(&camera->getWorld()));

                                scene->refresh();
                                scene->chunkSystem().update(1.0f / 60.0f);
                                scene->transformSystem().update();

                                if (target)
                                {
                                    target->bind(cubeFace);
                                    scene->renderSystem().predraw();
                                    
                                    float scaleFactor = ScreenUtilities::contentScaleFactor();
                                    unsigned int screenWidth = target->getWidth() / scaleFactor;
                                    unsigned int screenHeight = target->getHeight() / scaleFactor;
                                    
                                    scene->renderSystem().drawCamera(camera.get(), screenWidth, screenHeight);
                                    scene->renderSystem().postdraw();
                                    target->unbind();
                                }
                                else
                                {
                                            // Extract original viewport
                                    GLint viewport[4];
                                    glGetIntegerv( GL_VIEWPORT, viewport );
                                   
                                    float scaleFactor = ScreenUtilities::contentScaleFactor();
                                    unsigned int screenWidth = viewport[2] / scaleFactor;
                                    unsigned int screenHeight = viewport[3] / scaleFactor;
                                    
                                    scene->renderSystem().predraw();
                                    scene->renderSystem().drawCamera(camera.get(), screenWidth, screenHeight);
                                    scene->renderSystem().postdraw();
                                }
                               
                                return 0;
                           })
        .addCustomFunction("__tostring", [] ()
                           {
                               return "camera";
                           })
        .endClass()
        
        // Core Objects
        .beginClass<SafeEntity>("entity")
        .addProperty("active", &SafeEntity::isActive, &SafeEntity::setActive)
        .addPropertyReadOnly("activeInHierarchy", &SafeEntity::activeInHierarchy)
        .addFunction("add", static_cast<int(SafeEntity::*)(lua_State*)>(&SafeEntity::addComponent))
        .addFunction("get", static_cast<int(SafeEntity::*)(lua_State*)>(&SafeEntity::getComponent))
        .addFunction("remove", static_cast<int(SafeEntity::*)(lua_State*)>(&SafeEntity::removeComponent))
        .addFunction("destroy", &SafeEntity::destroy)
        
        // Transform Shortcuts
        .addProperty("position", &SafeEntity::getPosition, &SafeEntity::setPosition)
        .addProperty("x", &SafeEntity::getX, &SafeEntity::setX)
        .addProperty("y", &SafeEntity::getY, &SafeEntity::setY)
        .addProperty("z", &SafeEntity::getZ, &SafeEntity::setZ)
        .addProperty("rotation", &SafeEntity::getRotation, &SafeEntity::setRotation)
        .addProperty("scale", &SafeEntity::getScale, &SafeEntity::setScale)
        .addPropertyReadOnly("forward", &SafeEntity::forward)
        .addPropertyReadOnly("right", &SafeEntity::right)
        .addPropertyReadOnly("up", &SafeEntity::up)
        .addProperty("worldPosition", &SafeEntity::getWorldPosition, &SafeEntity::setWorldPosition)
        .addPropertyReadOnly("worldRotation", &SafeEntity::getWorldRotation)
        .addProperty("eulerAngles", &SafeEntity::getEulerAngles, &SafeEntity::setEulerAngles)
        
        .addFunction("transformPoint", &SafeEntity::transformPoint, LUA_ARGS(glm::vec3))
        .addFunction("transformDirection", &SafeEntity::transformDirection, LUA_ARGS(glm::vec3))
        .addFunction("inverseTransformPoint", &SafeEntity::inverseTransformPoint, LUA_ARGS(glm::vec3))
        .addFunction("inverseTransformDirection", &SafeEntity::inverseTransformDirection, LUA_ARGS(glm::vec3))
        
        
        
        // MeshRenderer shortcuts
        .addProperty("model", &SafeEntity::getMesh, &SafeEntity::setMesh)
        .addProperty("material", &SafeEntity::getMaterial, &SafeEntity::setMaterial)
        
        .addCustomFunction("__eq", [] (SafeEntity& lhs, SafeEntity& rhs)
                           {
                               return lhs == rhs;
                           })
        .addCustomFunction("__tostring", [](SafeEntity& entity)
                           {
                               if (entity.exists())
                               {
                                   return "entity";
                               }
                               else
                               {
                                   return "entity (destroyed)";
                               }
                           })

        .endClass()


        .beginClass<Scene>("scene")
        .addFactory([](lua_State* L)
                    {
                        int n = lua_gettop(L);
                        int width = n >= 2 ? (int)lua_tointeger(L, 2) : 1024;
                        int height = n >= 3 ? (int)lua_tointeger(L, 3) : 768;
                        
                        std::string projectPath;
                        if (FileUtilities::getAssetPackPath("Project", projectPath))
                        {
                            Scene* world = new Scene(projectPath.c_str(), width, height, L);
                            
                            LuaIntf::CppObjectSharedPtr<std::shared_ptr<Scene>, Scene>::pushToStack(L, world, false);
                            
                            auto scenePtr = Lua::get<std::shared_ptr<Scene>>(L, -1);
                            
                            world->setWeakSelf(scenePtr);
                            
                            return 1;
                        }
                        return 0;
                    })
        .addFunction("entity", &Scene::lua_createEntity)        
        .addPropertyReadOnly("camera", &Scene::lua_getCamera)
        .addPropertyReadOnly("sun", &Scene::lua_getSun)
        .addPropertyReadOnly("sky", &Scene::lua_getSkybox)
        .addPropertyReadOnly("voxels", &Scene::chunkSystem)
        .addPropertyReadOnly("physics", &Scene::bulletPhysicsSystem)
        .addPropertyReadOnly("ar", &Scene::arSystem)
        .addPropertyReadOnly("debug", &Scene::debugRenderer)
        .addProperty("fogEnabled", &Scene::lua_getFogEnabled, &Scene::lua_setFogEnabled)
        .addProperty("fogNear", &Scene::lua_getFogNear, &Scene::lua_setFogNear)
        .addProperty("fogFar", &Scene::lua_getFogFar, &Scene::lua_setFogFar)
        .addPropertyReadOnly("renderBatchCount", &Scene::getRenderBatchCount)
        .addPropertyReadOnly("renderBatchCullCount", &Scene::getRenderBatchCullCount)
        .addFunction("update", &Scene::update, LUA_ARGS(float))
        .addFunction("draw", &Scene::draw, LUA_ARGS())
        .addCustomFunction("__tostring", [] (Scene* scene)
                           {
                               return "scene";
                           })
        .endClass()

        .beginClass<ARSystem>("ar")
        .addStaticProperty("isSupported", &ARSystem::isSupported)
        .addStaticProperty("isFaceTrackingSupported", &ARSystem::isFaceTrackingSupported)
        .addPropertyReadOnly("isRunning", &ARSystem::isRunning)
        .addProperty("planeDetection", &ARSystem::getPlaneDetection, &ARSystem::setPlaneDetection)
        .addProperty("didAddAnchors", &ARSystem::getDidAddAnchors, &ARSystem::setDidAddAnchors)
        .addProperty("didUpdateAnchors", &ARSystem::getDidUpdateAnchors, &ARSystem::setDidUpdateAnchors)
        .addProperty("didRemoveAnchors", &ARSystem::getDidRemoveAnchors, &ARSystem::setDidRemoveAnchors)
        .addPropertyReadOnly("points", &ARSystem::points)
        .addPropertyReadOnly("trackingState", &ARSystem::getTrackingState)
        .addPropertyReadOnly("trackingStateReason", &ARSystem::getTrackingStateReason)
        .addFunction("hitTest", &ARSystem::lua_hitTest)
        .addFunction("run", &ARSystem::run, LUA_ARGS(_opt<ARSystemTrackingType>))
        .addFunction("pause", &ARSystem::pause)
#ifndef NO_TRUEDEPTH
        .addFunction("makeFaceModel", &ARSystem::makeFaceMesh, LUA_ARGS(std::map<std::string, float>))
#endif
        .addFunction("setTrackingImages", &ARSystem::setTrackingImages, LUA_ARGS(LuaRef, int))
        .endClass()
        
        .beginClass<ARSystem::Anchor>("anchor")
        .addVariable("type", &ARSystem::Anchor::type)
        .addVariable("identifier", &ARSystem::Anchor::identifier)
        .addPropertyReadOnly("position", &ARSystem::Anchor::getPosition)
        .addPropertyReadOnly("rotation", &ARSystem::Anchor::getRotation)
        .addPropertyReadOnly("extent", &ARSystem::Anchor::getExtent)
#ifndef NO_TRUEDEPTH
        .addPropertyReadOnly("faceModel", &ARSystem::Anchor::getFaceMesh)
        .addPropertyReadOnly("blendShapes", &ARSystem::Anchor::getBlendShapes)
        .addPropertyReadOnly("leftEyePosition", &ARSystem::Anchor::getLeftEyePosition)
        .addPropertyReadOnly("leftEyeRotation", &ARSystem::Anchor::getLeftEyeRotation)
        .addPropertyReadOnly("rightEyePosition", &ARSystem::Anchor::getRightEyePosition)
        .addPropertyReadOnly("rightEyeRotation", &ARSystem::Anchor::getRightEyeRotation)
#endif
        .addPropertyReadOnly("lookAtPoint", &ARSystem::Anchor::getLookAtPoint)
        .addPropertyReadOnly("physicalSize", &ARSystem::Anchor::getPhysicalSize)
        .endClass()

        .beginClass<ARSystem::HitTestResult>("hitTestResult")
        .addVariable("type", &ARSystem::HitTestResult::type)
        .addPropertyReadOnly("position", &ARSystem::HitTestResult::getPosition)
        .addPropertyReadOnly("rotation", &ARSystem::HitTestResult::getRotation)
        .addVariable("distance", &ARSystem::HitTestResult::distance)
        .endClass()
        
        .beginClass<ChunkSystem>("voxels")
        .addPropertyReadOnly("blocks", &ChunkSystem::getBlockset)
        .addPropertyReadOnly("visibleChunks", &ChunkSystem::visibleChunksCount)
        .addPropertyReadOnly("generatingChunks", &ChunkSystem::generatingChunksCount)
        .addPropertyReadOnly("meshingChunks", &ChunkSystem::meshingChunksCount)
        .addProperty("coordinates", &ChunkSystem::getViewerCoordinates, &ChunkSystem::setViewerCoordinates)
        .addProperty("visibleRadius", &ChunkSystem::getVisibleChunkRadius, &ChunkSystem::setVisibleChunkRadius)
        .addFunction("resize", &ChunkSystem::lua_resize)
        .addFunction("set", &ChunkSystem::lua_setBlock)
        .addFunction("get", &ChunkSystem::lua_getBlock)
        .addFunction("fill", &ChunkSystem::lua_fill)
        .addFunction("fillStyle", &ChunkSystem::lua_fillMode)
        .addFunction("find", &ChunkSystem::lua_find)
        .addFunction("block", &ChunkSystem::lua_block)
        .addFunction("sphere", &ChunkSystem::lua_sphere)
        .addFunction("box", &ChunkSystem::lua_box)
        .addFunction("line", &ChunkSystem::lua_line)
        .addFunction("updateBlock", &ChunkSystem::scheduleBlockUpdate, LUA_ARGS(int,int,int,long))
        .addFunction("raycast", &ChunkSystem::lua_raycast)
        .addFunction("generate", &ChunkSystem::generate, LUA_ARGS(std::string, std::string))
        .addFunction("isRegionLoaded", &ChunkSystem::lua_isRegionLoaded)
        .addFunction("iterateBounds", &ChunkSystem::lua_iterateBounds)
        .addFunction("enableStorage", &ChunkSystem::enableStorage, LUA_ARGS(std::string))
        .addFunction("disableStorage", &ChunkSystem::disableStorage)
        .addFunction("deleteStorage", &ChunkSystem::deleteStorage, LUA_ARGS(std::string))
        .addCustomFunction("__tostring", [] (Scene* scene)
                           {
                               return "voxels";
                           })
        .endClass();
        
        //.endModule();
        
        LuaBinding(module).beginClass<RenderTarget>("renderTarget")
        .addFactory([](lua_State* L)
        {
            int n = lua_gettop(L);
            RenderTarget* target = nullptr;
                    
            if (n >= 2)
            {
                if (isClass<Texture>(L, 2))
                {
                    TexturePtr texture = Lua::get<TexturePtr>(L, 2);
                    target = new RenderTarget(texture, Texture::Format::DEPTH32F);
                }
                else if (isClass<CubeTexture>(L, 2))
                {
                    CubeTexturePtr texture = Lua::get<CubeTexturePtr>(L, 2);
                    target = new RenderTarget(texture, Texture::Format::DEPTH32F);
                }
            }
            
            if (target)
            {
                LuaIntf::CppObjectSharedPtr<std::shared_ptr<RenderTarget>, RenderTarget>::pushToStack(L, target, false);
                return 1;
            }
            return 0;
        })
        .endClass();
        
        LuaBinding(module).beginClass<DebugRenderer>("DebugRenderer")
        .addCustomFunction("line", [] (lua_State* L)
                           {
                               DebugRenderer* debugRenderer = Lua::get<DebugRenderer*>(L, 1);
                               
                               glm::vec3 start = Lua::get<glm::vec3>(L, 2);
                               glm::vec3 end = Lua::get<glm::vec3>(L, 3);
                               color_type_t* color = checkcolor(L, 4);
                               
                               debugRenderer->drawLine(start, end, glm::vec4((int)color->r/255.0f,
                                                                             (int)color->g/255.0f,
                                                                             (int)color->b/255.0f,
                                                                             1.0f));
                               
                               return 0;
                           })
        .addCustomFunction("bounds", [] (lua_State* L)
                           {
                               DebugRenderer* debugRenderer = Lua::get<DebugRenderer*>(L, 1);
                               Bounds bounds = Lua::get<Bounds>(L, 2);
                               color_type_t* color = checkcolor(L, 3);
                               
                               debugRenderer->drawBounds(bounds, glm::vec4((int)color->r/255.0f,
                                                                           (int)color->g/255.0f,
                                                                           (int)color->b/255.0f,
                                                                           1.0f));
                            
                               return 0;
                           })
        .addCustomFunction("__tostring", [] (Scene* scene)
                           {
                               return "debug";
                           })
        .endClass();
        
        {
            auto entityClass = LuaBinding(module).beginClass<SafeEntity>("entity");
            
            // Workaround to allow nil property setting. Directly set setter and getter function for SafeEntity parent property
            using CppGetter = CppBindClassMethod<SafeEntity, int(SafeEntity::*)(lua_State*)>;
            using CppSetter = CppBindClassMethod<SafeEntity, int(SafeEntity::*)(lua_State*)>;
            entityClass.setMemberGetter("parent", LuaRef::createFunction(module.state(), &CppGetter::call, CppGetter::function(&SafeEntity::getParent)));
            entityClass.setMemberSetter("parent", LuaRef::createFunction(module.state(), &CppSetter::call, CppSetter::function(&SafeEntity::setParent)));
            
            entityClass.setMemberGetter("children", LuaRef::createFunction(module.state(), &CppGetter::call, CppGetter::function(&SafeEntity::lua_getChildren)));
        }

        {
            auto worldClass = LuaBinding(module).beginClass<Scene>("scene");

            using CppGetter = CppBindClassMethod<Scene, int(Scene::*)(lua_State*)>;
            using CppSetter = CppBindClassMethod<Scene, int(Scene::*)(lua_State*)>;

            worldClass.setMemberGetter("ambientColor", LuaRef::createFunction(module.state(), &CppGetter::call, CppGetter::function(&Scene::lua_getAmbientColor)));
            worldClass.setMemberSetter("ambientColor", LuaRef::createFunction(module.state(), &CppSetter::call, CppSetter::function(&Scene::lua_setAmbientColor)));

            worldClass.setMemberGetter("background", LuaRef::createFunction(module.state(), &CppGetter::call, CppGetter::function(&Scene::lua_getBackground)));
            worldClass.setMemberSetter("background", LuaRef::createFunction(module.state(), &CppSetter::call, CppSetter::function(&Scene::lua_setBackground)));

            worldClass.setMemberGetter("environment", LuaRef::createFunction(module.state(), &CppGetter::call, CppGetter::function(&Scene::lua_getEnvironment)));
            worldClass.setMemberSetter("environment", LuaRef::createFunction(module.state(), &CppSetter::call, CppSetter::function(&Scene::lua_setEnvironment)));
            
            worldClass.setMemberGetter("fogColor", LuaRef::createFunction(module.state(), &CppGetter::call, CppGetter::function(&Scene::lua_getFogColor)));
            worldClass.setMemberSetter("fogColor", LuaRef::createFunction(module.state(), &CppSetter::call, CppSetter::function(&Scene::lua_setFogColor)));
        }
        
        getSafeComponentRegistry(module.state())->registerSafeComponent<Camera, Camera, SafeCamera>(module.get("camera"),
        [] (lua_State* L, anax::Entity entity)
        {
            if (!entity.hasComponent<Camera>())
            {
                float screenWidth = Lua::getGlobal<float>(L, "WIDTH");
                float screenHeight = Lua::getGlobal<float>(L, "HEIGHT");
                
                float orthoSizeOrFovY = luaL_optnumber(L, 3, 45);
                float nearPlane = luaL_optnumber(L, 4, 0.1f);
                float farPlane = luaL_optnumber(L, 5, 1000.0f);
                bool ortho = lua_gettop(L) == 6 ? lua_toboolean(L, 6) : false;
                
                entity.addComponent<Camera>(orthoSizeOrFovY, screenWidth / screenHeight, nearPlane, farPlane, ortho);
                Lua::push(L, SafeCamera(entity));
                return 1;
            }
            return 0;
        });        
        
    }

    void register_chunk(LuaRef& module)
    {
        LuaBinding(module)
        
        .beginExtendClass<SafeChunk, SafeComponentBase>("volume")
        .addProperty("model", &SafeChunk::getMesh)
        .addFunction("size", &SafeChunk::lua_size)
        .addFunction("set", &SafeChunk::lua_setBlock)
        .addFunction("get", &SafeChunk::lua_getBlock)
        .addFunction("raycast", &SafeChunk::lua_raycast)
        .addFunction("clear", &SafeChunk::clear)
        .addFunction("resize", &SafeChunk::resize, LUA_ARGS(int, int, int))
        .addFunction("save", [] (SafeChunk* chunk, lua_State *L) {
            NSString *path = assetPathOnStackAtIndex(L, 2, 0);
            
            if( path ) {
                chunk->save(path.UTF8String);
            }
        })
        .addFunction("load", [] (SafeChunk* chunk, lua_State *L) {
            NSString *path = assetPathOnStackAtIndex(L, 2, AssetKeyStackOptionsMustExist);
            
            if( path ) {
                chunk->load(path.UTF8String);
            }
        })
        .addFunction("saveSnapshot", &SafeChunk::lua_saveSnapshot)
        .addFunction("loadSnapshot", &SafeChunk::lua_loadSnapshot)
        .addFunction("blockID", &SafeChunk::blockID, LUA_ARGS(const char*))
        .addFunction("setWithNoise", &SafeChunk::lua_setWithNoiseModule)
        .addFunction("updateBlock", &SafeChunk::lua_scheduleBlockUpdate)
        .addCustomFunction("__tostring", [] ()
                           {
                               return "volume";
                           })
        .endClass()
        
        .beginClass<ChunkSnapshot>("VolumeSnapshot")
        .addConstructor(LUA_ARGS())
        .endClass();
        
        getSafeComponentRegistry(module.state())->registerSafeComponent<Chunk, Chunk, SafeChunk>(module.get("volume"), [] (lua_State* L, anax::Entity entity)
        {
            if (!entity.hasComponent<Chunk>())
            {
                int n = lua_gettop(L);
                
                // entity:add(Volume)
                if (n == 2)
                {
                    entity.addComponent<Chunk>(glm::ivec3(0,0,0));
                }
                // entity:add(Volume, voxelAssetName)
                else if (n == 3)
                {
                    std::string fullpath = assetPathOnStackAtIndex(L, 3, 0).UTF8String;
                    
                    Chunk& chunk = entity.addComponent<Chunk>(glm::ivec3(0,0,0));
                    ChunkSerializer::loadChunk(fullpath, chunk);
                }
                // entity:add(Volume, x, y, z)
                else if (n == 5)
                {
                    glm::ivec3 size;
                    size.x = Lua::get<int>(L, 3);
                    size.y = Lua::get<int>(L, 4);
                    size.z = Lua::get<int>(L, 5);
                    entity.addComponent<Chunk>(size);
                }
                

                Lua::push(L, SafeChunk(entity));
                return 1;
            }
            return 0;
        });

    }

    int noiseModuleConstFactory(lua_State* L)
    {
        int n = lua_gettop(L);
        
        float constValue = 0;
        
        if (n == 2)
        {
            constValue = Lua::get<float>(L, 2);
        }
        
        Lua::pushNew<noise::module::Const>(L);
        noise::module::Const* constNoise = Lua::get<noise::module::Const*>(L, -1);
        constNoise->SetConstValue(constValue);
        
        return 1;
    }

    int noiseModuleSetSource(lua_State* L)
    {
        int n = lua_gettop(L);

        if (n == 3)
        {
            noise::module::Module* module = Lua::get<noise::module::Module*>(L, 1);
            int index = Lua::get<int>(L, 2);
            noise::module::Module* source = Lua::get<noise::module::Module*>(L, 3);
            
            if (index >= 0 && index < module->GetSourceModuleCount())
            {
                module->SetSourceModule(index, *source);
                
                lua_getuservalue(L, 1);
                if (lua_isnil(L, -1))
                {
                    lua_pop(L, 1);
                    lua_newtable(L);
                    lua_pushinteger(L, index+1);
                    lua_pushvalue(L, 3);
                    lua_settable(L, -3);
                    lua_setuservalue(L, 1);
                }
                else
                {
                    lua_pushinteger(L, index+1);
                    lua_pushvalue(L, 3);
                    lua_settable(L, -3);
                    lua_setuservalue(L, 1);
                }
            }
            else
            {
                throw LuaIntf::LuaException(std::string("Noise source module index out of range [") +
                                            std::to_string(0) +
                                            ", " +
                                            std::to_string(module->GetSourceModuleCount()) +
                                            ")");
            }
        }

        return 0;
    }

    void register_noise(LuaRef& module)
    {
        LuaBinding(module)
        
        .beginModule("noise")
            .beginClass<noise::module::Module>("module")
                .addFunction("getValue", &noise::module::Module::GetValue,
                             LUA_ARGS(_def<double, 0, 1>, _def<double, 0, 1>, _def<double, 0, 1>))
                .addFunction("__call", &noise::module::Module::GetValue,
                             LUA_ARGS(_def<double, 0, 1>, _def<double, 0, 1>, _def<double, 0, 1>))
                //.addFunction("setSource", &noise::module::Module::SetSourceModule, LUA_ARGS(int, noise::module::Module&))
                .addCustomFunction("setSource", &noiseModuleSetSource)
            .endClass()

            // Chunk Cache 2D
            .beginExtendClass<noise::module::ChunkCache2D, noise::module::Module>("chunkCache2D")
            .addConstructor(LUA_ARGS(SafeChunk))
            .endClass()
        
            // Perlin Noise
            .beginExtendClass<noise::module::Perlin, noise::module::Module>("perlin")
                .addConstructor(LUA_ARGS())
                .addProperty("frequency", &noise::module::Perlin::GetFrequency, &noise::module::Perlin::SetFrequency)
                .addProperty("octaves", &noise::module::Perlin::GetOctaveCount, &noise::module::Perlin::SetOctaveCount)
                .addProperty("persistence", &noise::module::Perlin::GetPersistence, &noise::module::Perlin::SetPersistence)
                .addProperty("seed", &noise::module::Perlin::GetSeed, &noise::module::Perlin::SetSeed)
                .addCustomFunction("__tostring", [] ()
                                   {
                                       return "noise.perlin";
                                   })

            .endClass()

            // RigidMulti Noise
            .beginExtendClass<noise::module::RidgedMulti, noise::module::Module>("rigidMulti")
                .addConstructor(LUA_ARGS())
                .addProperty("frequency", &noise::module::RidgedMulti::GetFrequency, &noise::module::RidgedMulti::SetFrequency)
                .addProperty("octaves", &noise::module::RidgedMulti::GetOctaveCount, &noise::module::RidgedMulti::SetOctaveCount)
                .addProperty("lacunarity", &noise::module::RidgedMulti::GetLacunarity, &noise::module::RidgedMulti::SetLacunarity)
                .addProperty("seed", &noise::module::RidgedMulti::GetSeed, &noise::module::RidgedMulti::SetSeed)
                .addCustomFunction("__tostring", [] ()
                                   {
                                       return "noise.rigidMulti";
                                   })

            .endClass()

            // Billow Noise
            .beginExtendClass<noise::module::Billow, noise::module::Module>("billow")
                .addConstructor(LUA_ARGS())
                .addProperty("frequency", &noise::module::Billow::GetFrequency, &noise::module::Billow::SetFrequency)
                .addProperty("octaves", &noise::module::Billow::GetOctaveCount, &noise::module::Billow::SetOctaveCount)
                .addProperty("persistence", &noise::module::Billow::GetPersistence, &noise::module::Billow::SetPersistence)
                .addProperty("lacunarity", &noise::module::Billow::GetLacunarity, &noise::module::Billow::SetLacunarity)
                .addProperty("seed", &noise::module::Billow::GetSeed, &noise::module::Billow::SetSeed)
                .addCustomFunction("__tostring", [] ()
                                   {
                                       return "noise.billow";
                                   })
            .endClass()

            // Turbulence Noise
            .beginExtendClass<noise::module::Turbulence, noise::module::Module>("turbulence")
                .addConstructor(LUA_ARGS())
                .addProperty("frequency", &noise::module::Turbulence::GetFrequency, &noise::module::Turbulence::SetFrequency)
                .addProperty("roughness", &noise::module::Turbulence::GetRoughnessCount, &noise::module::Turbulence::SetRoughness)
                .addProperty("power", &noise::module::Turbulence::GetPower, &noise::module::Turbulence::SetPower)
                .addProperty("seed", &noise::module::Turbulence::GetSeed, &noise::module::Turbulence::SetSeed)
                .addCustomFunction("__tostring", [] ()
                                   {
                                       return "noise.turbulence";
                                   })
            .endClass()
        
        
            // Cache
            .beginExtendClass<noise::module::Cache, noise::module::Module>("cache")
                .addCustomFunction("__tostring", [] ()
                                   {
                                       return "noise.cache";
                                   })
            .endClass()
        
            // Const
            .beginExtendClass<noise::module::Const, noise::module::Module>("const")
                .addFactory(noiseModuleConstFactory)
                .addProperty("value", &noise::module::Const::GetConstValue, &noise::module::Const::SetConstValue)
                .addCustomFunction("__tostring", [] ()
                                   {
                                       return "noise.const";
                                   })
            .endClass()
        
            // Select
            .beginExtendClass<noise::module::Select, noise::module::Module>("select")
                .addConstructor(LUA_ARGS())
                .addProperty("falloff", &noise::module::Select::GetEdgeFalloff, &noise::module::Select::SetEdgeFalloff)

                .addFunction("setBounds", &noise::module::Select::SetBounds, LUA_ARGS(double, double))
                .addCustomFunction("__tostring", [] ()
                                   {
                                       return "noise.select";
                                   })
            .endClass()

            // Gradient
            .beginExtendClass<noise::module::Gradient, noise::module::Module>("gradient")
                .addConstructor(LUA_ARGS())
                .addCustomFunction("__tostring", [] ()
                                   {
                                       return "noise.gradient";
                                   })
            .endClass()

            // Multiply
            .beginExtendClass<noise::module::Multiply, noise::module::Module>("multiply")
                .addConstructor(LUA_ARGS())
                .addCustomFunction("__tostring", [] ()
                                   {
                                       return "noise.multiply";
                                   })
            .endClass()

            // Min
            .beginExtendClass<noise::module::Min, noise::module::Module>("min")
                .addConstructor(LUA_ARGS())
                .addCustomFunction("__tostring", [] ()
                                   {
                                       return "noise.min";
                                   })
            .endClass()

            // Max
            .beginExtendClass<noise::module::Max, noise::module::Module>("max")
                .addConstructor(LUA_ARGS())
                .addCustomFunction("__tostring", [] ()
                                   {
                                       return "noise.max";
                                   })
            .endClass()

            // Add
            .beginExtendClass<noise::module::Add, noise::module::Module>("add")
                .addConstructor(LUA_ARGS())
                .addCustomFunction("__tostring", [] ()
                                   {
                                       return "noise.add";
                                   })
            .endClass()

            // Invert
            .beginExtendClass<noise::module::Invert, noise::module::Module>("invert")
                .addConstructor(LUA_ARGS())
                .addCustomFunction("__tostring", [] ()
                                   {
                                       return "noise.invert";
                                   })
            .endClass()
        
            // Abs
            .beginExtendClass<noise::module::Abs, noise::module::Module>("abs")
                .addConstructor(LUA_ARGS())
                .addCustomFunction("__tostring", [] ()
                                   {
                                       return "noise.abs";
                                   })
            .endClass()
        
            // Merge
            .beginExtendClass<noise::module::Merge, noise::module::Module>("merge")
                .addConstructor(LUA_ARGS())
                .addCustomFunction("__tostring", [] ()
                                   {
                                       return "noise.merge";
                                   })
            .endClass()
        
            // Scale Bias
            .beginExtendClass<noise::module::ScaleBias, noise::module::Module>("scaleOffset")
                .addConstructor(LUA_ARGS())
                .addProperty("scale", &noise::module::ScaleBias::GetScale, &noise::module::ScaleBias::SetScale)
                .addProperty("offset", &noise::module::ScaleBias::GetBias, &noise::module::ScaleBias::SetBias)
                .addCustomFunction("__tostring", [] ()
                                   {
                                       return "noise.scaleOffset";
                                   })
            .endClass()

            // Displace
            .beginExtendClass<noise::module::Displace, noise::module::Module>("displace")
                .addConstructor(LUA_ARGS())
    //            .addProperty("x", &noise::module::Displace::GetXDisplaceModule, &noise::module::Displace::SetXDisplaceModule)
    //            .addProperty("y", &noise::module::Displace::GetYDisplaceModule, &noise::module::Displace::SetYDisplaceModule)
    //            .addProperty("z", &noise::module::Displace::GetZDisplaceModule, &noise::module::Displace::SetZDisplaceModule)
                .addCustomFunction("__tostring", [] ()
                                   {
                                       return "noise.displace";
                                   })
            .endClass()

            // Scale Point
            .beginExtendClass<noise::module::ScalePoint, noise::module::Module>("scale")
                .addFactory([] (float x = 1, float y = 1, float z = 1)
                            {
                                auto module = std::make_shared<noise::module::ScalePoint>();
                                module->SetScale(x, y, z);
                                return module;
                            }, LUA_ARGS(_opt<float>, _opt<float>, _opt<float>))
                .addProperty("x", &noise::module::ScalePoint::GetXScale, &noise::module::ScalePoint::SetXScale)
                .addProperty("y", &noise::module::ScalePoint::GetYScale, &noise::module::ScalePoint::SetYScale)
                .addProperty("z", &noise::module::ScalePoint::GetZScale, &noise::module::ScalePoint::SetZScale)
        
                .addCustomFunction("__tostring", [] ()
                                   {
                                       return "noise.scale";
                                   })

            .endClass()
        
            
        .endModule(); // End noise module
    }
    
    SafeComponentRegistry* getSafeComponentRegistry(lua_State* L)
    {
        lua_pushlightuserdata(L, (void*)SafeComponentRegistryKey);
        lua_gettable(L, LUA_REGISTRYINDEX);
        return Lua::pop<SafeComponentRegistry*>(L);
    }

    void register_safecomponent(LuaRef& module)
    {
        // Store safe component registry inside the lua global registry table
        LuaBinding(module).beginClass<SafeComponentRegistry>("SafeComponentRegistry")
        .endClass();
        
        lua_pushlightuserdata(module.state(), (void*)SafeComponentRegistryKey);
        Lua::pushNew<SafeComponentRegistry>(module.state());
        lua_settable(module.state(), LUA_REGISTRYINDEX);
        
        
        LuaBinding(module)
        .beginClass<SafeComponentBase>("component")
        .addPropertyReadOnly("entity", &SafeComponentBase::getSafeEntity)
        .endClass();
    }
    
    int export_codeacraft(lua_State* L)
    {
        // Constants
        Lua::setGlobal(L, "REPLACE", VoxelStyle::FillStyle::Replace);
        Lua::setGlobal(L, "UNION", VoxelStyle::FillStyle::Union);
        Lua::setGlobal(L, "INTERSECT", VoxelStyle::FillStyle::Intersect);
        Lua::setGlobal(L, "CLEAR", VoxelStyle::FillStyle::Clear);

        Lua::setGlobal(L, "DIRECTIONAL", Light::Type::Directional);
        Lua::setGlobal(L, "POINT", Light::Type::Point);
        Lua::setGlobal(L, "SPOT", Light::Type::Spot);

        // Facing Constants
        Lua::setGlobal(L, "NORTH", BlockFace::North);
        Lua::setGlobal(L, "EAST", BlockFace::East);
        Lua::setGlobal(L, "SOUTH", BlockFace::South);
        Lua::setGlobal(L, "WEST", BlockFace::West);
        Lua::setGlobal(L, "UP", BlockFace::Up);
        Lua::setGlobal(L, "DOWN", BlockFace::Down);
        Lua::setGlobal(L, "NONE", BlockFace::None);
        Lua::setGlobal(L, "ALL", BlockFace::All);
        
        // Block State Constants
        Lua::setGlobal(L, "BLOCK_ID", Chunk::LuaBlockReturnType::BLOCK_ID);
        Lua::setGlobal(L, "BLOCK_NAME", Chunk::LuaBlockReturnType::BLOCK_NAME);
        Lua::setGlobal(L, "BLOCK_ENTITY", Chunk::LuaBlockReturnType::BLOCK_ENTITY);
        Lua::setGlobal(L, "BLOCK_STATE", Chunk::LuaBlockReturnType::BLOCK_STATE);
        Lua::setGlobal(L, "COLOR", Chunk::LuaBlockReturnType::COLOR);
        Lua::setGlobal(L, "TORCH_LIGHT", Chunk::LuaBlockReturnType::TORCH_LIGHT);
        Lua::setGlobal(L, "LIGHT", Chunk::LuaBlockReturnType::LIGHT);
        
        // Block Geometry Constants
        Lua::setGlobal(L, "EMPTY", BlockGeometry::Empty);
        Lua::setGlobal(L, "SOLID", BlockGeometry::Solid);
        Lua::setGlobal(L, "TRANSPARENT", BlockGeometry::Transparent);

        Lua::setGlobal(L, "OPAQUE", BlockRenderPass::Opaque);
        Lua::setGlobal(L, "TRANSLUCENT", BlockRenderPass::Translucent);

        // ARSystem constants
        Lua::setGlobal(L, "AR_WORLD_TRACKING", ARSystemTrackingType::WorldTracking);
        Lua::setGlobal(L, "AR_FACE_TRACKING", ARSystemTrackingType::FaceTracking);
        
        Lua::setGlobal(L, "AR_NOT_AVAILABLE", ARSystemTrackingState::NotAvailable);
        Lua::setGlobal(L, "AR_LIMITED", ARSystemTrackingState::Limited);
        Lua::setGlobal(L, "AR_NORMAL", ARSystemTrackingState::Normal);
        Lua::setGlobal(L, "AR_NONE", ARSystemTrackingStateReason::None);
        Lua::setGlobal(L, "AR_EXCESSIVE_MOTION", ARSystemTrackingStateReason::ExcessiveMotion);
        Lua::setGlobal(L, "AR_INSUFFICIENT_FEATURES", ARSystemTrackingStateReason::InsufficientFeatures);
        
        Lua::setGlobal(L, "AR_FEATURE_POINT", ARSystemHitTestResultType::FeaturePoint);
        Lua::setGlobal(L, "AR_ESTIMATED_PLANE", ARSystemHitTestResultType::EstimatedHorizontalPlane);
        Lua::setGlobal(L, "AR_EXISTING_PLANE", ARSystemHitTestResultType::ExistingPlane);
        Lua::setGlobal(L, "AR_EXISTING_PLANE_CLIPPED", ARSystemHitTestResultType::ExistingPlaneUsingExtent);

        Lua::setGlobal(L, "AR_POINT", ARSystemAnchorType::Point);
        Lua::setGlobal(L, "AR_PLANE", ARSystemAnchorType::Plane);
        Lua::setGlobal(L, "AR_FACE", ARSystemAnchorType::Face);
        Lua::setGlobal(L, "AR_IMAGE", ARSystemAnchorType::Image);
        
        Lua::setGlobal(L, "COLOR_MASK_NONE", ColorMask::None);
        Lua::setGlobal(L, "COLOR_MASK_RED", ColorMask::Red);
        Lua::setGlobal(L, "COLOR_MASK_GREEN", ColorMask::Green);
        Lua::setGlobal(L, "COLOR_MASK_BLUE", ColorMask::Blue);
        Lua::setGlobal(L, "COLOR_MASK_ALPHA", ColorMask::Alpha);
        Lua::setGlobal(L, "COLOR_MASK_RGB", ColorMask::RGB);
        Lua::setGlobal(L, "COLOR_MASK_RGBA", ColorMask::RGBA);
        
        return 0;
    }
    
    int luaopen_vector_math(lua_State* L)
    {
        auto fromToRotation = [] (glm::vec3 u, glm::vec3 v)
        {
            const float tolerance = 0.000001;
            
            if( glm::length(glm::cross(v, u)) < tolerance ) {
                if( glm::dot(v, u) >= -tolerance ) {
                    return glm::quat(1, 0, 0, 0);
                }
            
                u = glm::normalize(u);
                
                float a = abs(u.x);
                float b = abs(u.y);
                float c = abs(u.z);
                
                if( a < b && a < c ) {
                    v = glm::vec3(0, -u.z, u.y);
                } else if( b < c ) {
                    v = glm::vec3(u.z, 0, -u.x);
                } else {
                    v = glm::vec3(u.y, -u.x, 0);
                }
            } else {
                u = glm::normalize(u);
                v = u + glm::normalize(v);
            }
            
            v = glm::normalize(v);
            
            float d = glm::dot(u, v);
            u = glm::cross(u, v);
            return glm::quat(d, u.x, u.y, u.z);
        };
        
        LuaBinding(L)
        
        .beginClass<glm::quat>("quat")
        .addConstructor(LUA_ARGS(_def_float(1.0f), _def_float(0.0f), _def_float(0.0f), _def_float(0.0f)))
        .addVariable("x", &glm::quat::x)
        .addVariable("y", &glm::quat::y)
        .addVariable("z", &glm::quat::z)
        .addVariable("w", &glm::quat::w)
        .addCustomFunction("__unm", [](glm::quat& q)
                           {
                               return -q;
                           })
        .addCustomFunction("__mul", [](glm::quat& lhs, glm::quat& rhs)
                           {
                               glm::quat q = lhs * rhs;
                               return q;
                           })
        .addCustomFunction("__eq", [](glm::quat& lhs, glm::quat& rhs)
                           {
                               return lhs == rhs;
                           })
        .addCustomFunction("__tostring", [](glm::quat& q)
                           {
                               return "(" + std::to_string(q.w) + ", " +
                               std::to_string(q.x) + ", " +
                               std::to_string(q.y) + ", " +
                               std::to_string(q.z) + ")";
                           })
        .addCustomFunction("slerp", [] (glm::quat& q1, glm::quat& q2, float t)
                           {
                               return glm::slerp(q1, q2, t);
                           })
        .addCustomFunction("angles", [] (glm::quat& q)
                           {
                               return glm::degrees(glm::eulerAngles(q));
                           })
        .addCustomFunction("normalized", [] (glm::quat& q)
                           {
                               return glm::normalize(q);
                           })
        .addCustomFunction("normalize", [] (glm::quat& q)
                           {
                               q = glm::normalize(q);
                           })
        .addCustomFunction("conjugate", [] (glm::quat& q)
                           {
                               return glm::conjugate(q);
                           })
        .addCustomFunction("len", [] (glm::quat& q)
                           {
                               return glm::length(q);
                           })
        .addCustomFunction("lenSqr", [] (glm::quat& q)
                           {
                               return glm::length2(q);
                           })
        .addStaticFunction("angleAxis", [] (float angle, glm::vec3 axis)
                           {
                               return glm::angleAxis(glm::radians(angle), axis);
                           })
        .addStaticFunction("eulerAngles", [] (float x, float y, float z)
                           {
                               return (glm::quat)glm::orientate3(glm::radians(glm::vec3(x,z,y)));
                           })
        .addStaticFunction("lookRotation", [] (glm::vec3 dir, glm::vec3 up)
                           {
                               return lookRotation(dir, up);
                           })
        .addStaticFunction("fromToRotation", fromToRotation)
        .endClass()
        
        .beginClass<Bounds>("bounds")
        .addConstructor(LUA_ARGS(glm::vec3, glm::vec3))
        .addPropertyReadOnly("min", &Bounds::min)
        .addPropertyReadOnly("max", &Bounds::max)
        .addPropertyReadOnly("valid", &Bounds::isValid)
        .addPropertyReadOnly("center", &Bounds::center)
        .addPropertyReadOnly("offset", &Bounds::offset)
        .addPropertyReadOnly("size", &Bounds::size)
        .addCustomFunction("intersects", [] (Bounds& bounds, lua_State* L)
                           {
                               int n = lua_gettop(L);
                   
                               bool result = false;
                   
                               //bounds:intersects(bounds)
                               if (n == 2)
                               {
                                   Bounds b = Lua::get<Bounds>(L, 2);
                                   result = bounds.intersects(b);
                               }
                               //bounds:intersects(origin, direction)
                               else if (n == 3)
                               {
                                   glm::vec3 origin = Lua::get<glm::vec3>(L, 2);
                                   glm::vec3 dir = glm::normalize(Lua::get<glm::vec3>(L, 3));
                                   result = bounds.intersects(origin, dir);
                               }
                   
                               return result;
                           })
        .addFunction("encapsulate", &Bounds::encapsulate, LUA_ARGS(glm::vec3))
        .addFunction("translate", &Bounds::translate, LUA_ARGS(glm::vec3))
        .addFunction("set", &Bounds::setWithSizeOffset, LUA_ARGS(glm::vec3, glm::vec3))
        .endClass();
        
        //        .beginClass<Random>("Random")
        //            .addConstructor(LUA_ARGS(int))
        //            .addFunction("__call", &Random::__call)
        //        .endClass();
        
        return 0;
    }
    
    int luaopen_material(lua_State* L)
    {
        LuaRef module = LuaRef::createTable(L);
        
        module.setMetaTable(module);
        module.rawset("__index", &CppBindModuleMetaMethod::index);
        module.rawset("__newindex", &CppBindModuleMetaMethod::newIndex);
        module.rawset("___getters", LuaRef::createTable(L));
        module.rawset("___setters", LuaRef::createTable(L));

        register_material(module);
        luaopen_vec2(L);
        luaopen_vec3(L);
        luaopen_vec4(L);
        
        module.pushToStack();
        return 1;
    }   
    
    int luaopen_codeacraft(lua_State* L)
    {
        LuaRef module = LuaRef::createTable(L);
        
        //std::string type_name = "module<" + getFullName(m_meta, name) + ">";
        
        module.setMetaTable(module);
        module.rawset("__index", &CppBindModuleMetaMethod::index);
        module.rawset("__newindex", &CppBindModuleMetaMethod::newIndex);
        module.rawset("___getters", LuaRef::createTable(L));
        module.rawset("___setters", LuaRef::createTable(L));
        module.rawset("__call", export_codeacraft);
        module.rawset("export", export_codeacraft);
                
        register_safecomponent(module);
        register_material(module);
        register_blockset(module);
        register_chunk(module);
        register_mesh(module);
        register_physics(module);
        register_world(module);
        register_noise(module);
        register_misc(module);
        
        module.pushToStack();
        return 1;
    }
    
    void register_codeacraft_fake(lua_State* L)
    {
        std::string path = FileUtilities::getBundlePath() + "/craft_fake.lua";
        LuaState(L).doFile(path.c_str());
    }
}
