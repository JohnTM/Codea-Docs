//
//  sound_source.c
//  Runtime
//
//  Created by John Millard on 15/06/13.
//  Copyright (c) 2013 Two Lives Left. All rights reserved.
//

#import "soundsource.h"

#import "ALSoundSource.h"

#include "lua.h"
#include "lualib.h"
#include "lauxlib.h"

#define SOUNDSOURCETYPE CODEA_SOUNDSOURCELIBNAME
#define SOUNDSOURCESIZE sizeof(soundsource_type)

soundsource_type* tosoundsource(lua_State* L, int i)
{
    return (soundsource_type*)luaL_checkudata(L, i, SOUNDSOURCETYPE);
}

soundsource_type* check_soundsource(lua_State *L, int i)
{
    if (luaL_checkudata(L,i,SOUNDSOURCETYPE) == NULL)
    {
        luaL_argerror(L, i, SOUNDSOURCETYPE);
    }
    
    return lua_touserdata(L,i);
}

static soundsource_type* Pnew( lua_State *L )
{
    soundsource_type *s = lua_newuserdata(L,SOUNDSOURCESIZE);
    luaL_getmetatable(L, SOUNDSOURCETYPE);
    lua_setmetatable(L, -2);
    return s;
}

int push_soundsource( lua_State *L, id<ALSoundSource> source )
{
    soundsource_type *s = Pnew(L);
    s->source = (__bridge_retained void*)source;
    return 1;
}

static int Lset( lua_State *L )
{
    soundsource_type *s = check_soundsource(L, 1);
    id<ALSoundSource> source = (__bridge id<ALSoundSource>)s->source;
    
    const char* c = luaL_checkstring(L,2);
 
    if( strcmp(c, "volume") == 0 )
    {
        [source setVolume:lua_tonumber(L, 3)];
    }
    else if( strcmp(c, "pitch") == 0 )
    {
        [source setPitch:lua_tonumber(L, 3)];
    }
    else if( strcmp(c, "pan") == 0 )
    {
        [source setPan:lua_tonumber(L, 3)];
    }
    else if( strcmp(c, "looping") == 0 )
    {
        [source setLooping:lua_toboolean(L, 3)];
    }
    else if( strcmp(c, "paused") == 0 )
    {
        [source setPaused:lua_toboolean(L, 3)];
    }
    else if( strcmp(c, "muted") == 0 )
    {
        [source setMuted:lua_toboolean(L, 3)];
    }

    return 0;
}

static int Lget( lua_State *L )
{
    soundsource_type *s = check_soundsource(L, 1);
    id<ALSoundSource> source = (__bridge id<ALSoundSource>)s->source;
    
    const char* c = luaL_checkstring(L,2);
    
    if( strcmp(c, "volume") == 0 )
    {
        lua_pushnumber(L, [source volume]);
    }
    else if( strcmp(c, "pitch") == 0 )
    {
        lua_pushnumber(L, [source pitch]);
    }
    else if( strcmp(c, "pan") == 0 )
    {
        lua_pushnumber(L, [source pan]);
    }
    else if( strcmp(c, "looping") == 0 )
    {
        lua_pushboolean(L, [source looping]);
    }
    else if( strcmp(c, "paused") == 0 )
    {
        lua_pushboolean(L, [source paused]);
    }
    else if( strcmp(c, "muted") == 0 )
    {
        lua_pushboolean(L, [source muted]);
    }
    else if( strcmp(c, "playing") == 0 )
    {
        lua_pushboolean(L, [source playing]);
    }    
    else
    {
        //Load the metatable and value for key
        luaL_getmetatable(L, SOUNDSOURCETYPE);
        lua_pushstring(L, c);
        lua_gettable(L, -2);
    }
    
    return 1;
}

static int Lgc( lua_State *L)
{
    soundsource_type *s = check_soundsource(L, 1);
    id<ALSoundSource> source = (__bridge_transfer id<ALSoundSource>)s->source;
    source = nil;
    
    return 0;
}

static int Ltostring(lua_State *L)
{
//    soundsource_type *s = Pget(L,1);
    lua_pushfstring(L,"Soundsource: ");
    return 1;
}

static int Lstop(lua_State *L)
{
    soundsource_type *s = check_soundsource(L, 1);
    id<ALSoundSource> source = (__bridge id<ALSoundSource>)s->source;
    [source stop];
    return 0;
}

static int Lrewind(lua_State *L)
{
    soundsource_type *s = check_soundsource(L, 1);
    id<ALSoundSource> source = (__bridge id<ALSoundSource>)s->source;
    [source rewind];
    return 0;
}

static int LfadeTo(lua_State *L)
{
    soundsource_type *s = check_soundsource(L, 1);
    id<ALSoundSource> source = (__bridge id<ALSoundSource>)s->source;
    
    int n = lua_gettop(L);
    
    if (n >= 2)
    {
        [source fadeTo:lua_tonumber(L, 2) duration:lua_tonumber(L, 3) target:nil selector:NULL];
    }
    else
    {
        // TODO: argument validation and error checks
    }
    
    return 0;
}

static int LstopFade(lua_State *L)
{
    soundsource_type *s = check_soundsource(L, 1);
    id<ALSoundSource> source = (__bridge id<ALSoundSource>)s->source;
    [source stopFade];
    
    return 0;
}

static int LpitchTo(lua_State *L)
{
    soundsource_type *s = check_soundsource(L, 1);
    id<ALSoundSource> source = (__bridge id<ALSoundSource>)s->source;

    int n = lua_gettop(L);
    
    if (n >= 2)
    {
        [source pitchTo:lua_tonumber(L, 2) duration:lua_tonumber(L, 3) target:nil selector:NULL];
    }
    else
    {
        // TODO: argument validation and error checks
    }
    
    return 0;
}

static int LstopPitch(lua_State *L)
{
    soundsource_type *s = check_soundsource(L, 1);
    id<ALSoundSource> source = (__bridge id<ALSoundSource>)s->source;
    [source stopPitch];
    
    return 0;
}

static int LpanTo(lua_State *L)
{
    soundsource_type *s = check_soundsource(L, 1);
    id<ALSoundSource> source = (__bridge id<ALSoundSource>)s->source;

    int n = lua_gettop(L);
    
    if (n >= 2)
    {
        [source panTo:lua_tonumber(L, 2) duration:lua_tonumber(L, 3) target:nil selector:NULL];
    }
    else
    {
        // TODO: argument validation and error checks
    }
    
    return 0;
}

static int LstopPan(lua_State *L)
{
    soundsource_type *s = check_soundsource(L, 1);
    id<ALSoundSource> source = (__bridge id<ALSoundSource>)s->source;
    [source stopPan];
    
    return 0;
}

static int LstopActions(lua_State *L)
{
    soundsource_type *s = check_soundsource(L, 1);
    id<ALSoundSource> source = (__bridge id<ALSoundSource>)s->source;
    [source stopActions];
    
    return 0;
}

static const luaL_Reg R[] =
{
    { "__index", Lget },
    { "__newindex", Lset },
    { "__tostring", Ltostring },
    { "__gc", Lgc },
    { "stop", Lstop },
    { "rewind", Lrewind },
    { "fadeTo", LfadeTo },
    { "stopFade", LstopFade },
    { "pitchTo", LpitchTo },
    { "stopPitch", LstopPitch },
    { "panTo", LpanTo },
    { "stopPan", LstopPan },
    { "stopActions", LstopActions },
    { NULL, NULL }
};

LUALIB_API int luaopen_soundsource(lua_State *L)
{
    luaL_newmetatable(L,SOUNDSOURCETYPE);
    luaL_setfuncs(L, R, 0);
    return 0;
}