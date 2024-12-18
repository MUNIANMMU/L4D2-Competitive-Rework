#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#undef REQUIRE_PLUGIN
#include <left4dhooks>
#include <c4s2_ghost>

float		  g_fUnfreezeTime[MAXPLAYERS + 1];
bool		  g_bPluginEnable, g_bGameStart;
ConVar		  g_hItemsEnable;
GlobalForward g_hOnGhostTouchMine, g_hOnSoldierInSmoke;
Handle		  g_hMineTrine;

public Plugin myinfo =
{
	name		= "C4S2 Ghost - Grenades",
	author		= "Nepkey",
	description = "幽灵模式附加插件 - 生还者特殊投掷",
	version		= "1.1 - 2024.11.4",
	url			= "https://space.bilibili.com/436650372"
};

//---------------------------------------------------------------
//							基础设置
//---------------------------------------------------------------
public void OnPluginStart()
{
	g_hMineTrine		= CreateTrie();
	g_hOnGhostTouchMine = new GlobalForward("OnGhostTouchMine", ET_Ignore, Param_Cell, Param_Cell);
	g_hOnSoldierInSmoke = new GlobalForward("OnSoldierHitBySmoke", ET_Ignore, Param_Cell);
}

public void OnMapStart()
{
	g_bGameStart = false;
}

public void C4S2Ghost_OnRoundStart_Post(bool gamestart)
{
	ClearTrie(g_hMineTrine);
	g_bGameStart = gamestart;
	for (int i = 1; i <= MaxClients; i++)
	{
		g_fUnfreezeTime[i] = 0.0;
	}
}

public void C4S2_OnGameover()
{
	g_bGameStart = false;
}

public void OnAllPluginsLoaded()
{
	g_bPluginEnable = LibraryExists("c4s2_ghost");
	g_hItemsEnable	= FindConVar("c4s2_ghost_special_items");
}

public void OnLibraryAdded(const char[] name)
{
	if (StrEqual(name, "c4s2_ghost")) g_bPluginEnable = true;
}

public void OnLibraryRemoved(const char[] name)
{
	if (StrEqual(name, "c4s2_ghost")) g_bPluginEnable = false;
}

public void OnEntityCreated(int entity)
{
	if (!g_bPluginEnable || !g_bGameStart || !g_hItemsEnable.BoolValue) return;
	char sname[64];
	GetEntityClassname(entity, sname, sizeof(sname));
	if (StrEqual(sname, "pipe_bomb_projectile"))
	{
		//需要加一帧才能识别投掷者
		RequestFrame(OnPipeBombCreated_NextFrame, entity);
	}
}

void OnPipeBombCreated_NextFrame(int entity)
{
	int thrower = GetEntPropEnt(entity, Prop_Data, "m_hThrower");
	CreteLandmine(thrower);
	PrecacheSound("player/orch_hit_csharp_short.wav");
	EmitSoundToClient(thrower, "player/orch_hit_csharp_short.wav", .volume = 0.5);
	PrecacheSound("player/laser_on.wav");
	EmitSoundToClient(thrower, "player/laser_on.wav");
	AcceptEntityInput(entity, "Kill");
}

public void OnEntityDestroyed(int entity)
{
	if (!g_bPluginEnable || !g_bGameStart || !g_hItemsEnable.BoolValue) return;
	char sname[64];
	GetEntityClassname(entity, sname, sizeof(sname));
	if (StrEqual(sname, "vomitjar_projectile"))
	{
		float pos[3];
		GetEntPropVector(entity, Prop_Data, "m_vecAbsOrigin", pos);
		CreateSmoke(pos);

		for (int i = 1; i <= MaxClients; i++)
		{
			if (IsClientInGame(i) && IsPlayerAlive(i) && GetEntityDistance(i, entity) <= 500.0)
			{
				if (IsClientInGhost(i))
				{
					g_fUnfreezeTime[i] = GetGameTime() + 5.0;
					PrefetchSound("physics/glass/glass_impact_bullet4.wav");
					EmitSoundToClient(i, "physics/glass/glass_impact_bullet4.wav", .volume = 0.5);
				}
				else if (IsClientInSoldier(i))
				{
					//转发给其他插件
					Call_StartForward(g_hOnSoldierInSmoke);
					Call_PushCell(i);
					Call_Finish();
				}
			}
		}
	}
}

// 地雷相关
void CreteLandmine(int client)
{
	float vOrigin[3];
	float vAngles[3];
	GetClientAbsAngles(client, vAngles);
	GetClientFootOrigin(client, vOrigin);
	//修正地雷的视觉效果
	vOrigin[2] += 2.5;
	int iEntity = CreateEntityByName("prop_dynamic_override");
	if (iEntity == -1)
	{
		return;
	}
	TeleportEntity(iEntity, vOrigin, vAngles, NULL_VECTOR);
	char sModelName[PLATFORM_MAX_PATH];
	Format(sModelName, sizeof(sModelName), "models/props_junk/garbage_hubcap01a.mdl");
	PrecacheModel(sModelName, true);
	SetEntityModel(iEntity, sModelName);
	DispatchKeyValue(iEntity, "disableshadows", "1");
	SetEntPropEnt(iEntity, Prop_Send, "m_hOwnerEntity", client);

	SetEntProp(iEntity, Prop_Data, "m_nSolidType", 6);
	DispatchSpawn(iEntity);

	// SDKHook(iEntity, SDKHook_SetTransmit, OnMineTransmit);
	SDKHook(iEntity, SDKHook_Touch, OnMineTouch);
	CreateMineDefuseButton(iEntity);
}
/*
Action OnMineTransmit(int iEntity, int client)
{
	if (IsClientInGhost(client))
	{
		return Plugin_Handled;
	}
	else
	{
		return Plugin_Continue;
	}
}
*/
Action OnMineTouch(int entity, int other)
{
	if (!IsValidClientIndex(other) || IsClientInSoldier(other))
	{
		return Plugin_Continue;
	}
	int iParent = GetEntPropEnt(entity, Prop_Send, "m_hOwnerEntity");
	//向地雷的主人发出声音, 提醒有幽灵踩中地雷。
	PrecacheSound("weapons/hegrenade/beep.wav");
	if (IsClientInGame(iParent) && IsClientInSoldier(iParent))
	{
		EmitSoundToClient(iParent, "weapons/hegrenade/beep.wav");
	}

	//在地雷身上发出声音, 提醒周围的生还
	float pos[3];
	PrecacheSound("weapons/grenade_launcher/grenadefire/grenade_launcher_fire_1.wav");
	GetEntPropVector(entity, Prop_Data, "m_vecAbsOrigin", pos);
	EmitAmbientSound("weapons/grenade_launcher/grenadefire/grenade_launcher_fire_1.wav", pos, entity, .vol = 1.0);

	//转发给其他插件
	Call_StartForward(g_hOnGhostTouchMine);
	Call_PushCell(other);
	Call_PushCell(iParent);
	Call_Finish();

	//致盲幽灵, 提醒其踩中了探测地雷。
	DataPack dpin = new DataPack();
	dpin.WriteCell(other);
	dpin.WriteCell(1);
	dpin.WriteCell(1.0);
	DataPack dpout = new DataPack();
	dpout.WriteCell(other);
	dpout.WriteCell(0);
	dpout.WriteCell(1.0);
	CreateTimer(0.01, FlashBomb, dpin, TIMER_FLAG_NO_MAPCHANGE);
	CreateTimer(2.0, FlashBomb, dpout, TIMER_FLAG_NO_MAPCHANGE);

	// 销毁地雷本体和按钮
	KillBtn(entity);
	AcceptEntityInput(entity, "Kill");
	return Plugin_Continue;
}

Action FlashBomb(Handle timer, DataPack dp)
{
	dp.Reset();
	UserMsg g_FadeUserMsgId;
	int		clients[2];
	clients[0]	   = dp.ReadCell();
	int	  isfadein = dp.ReadCell();
	float percent  = dp.ReadCell();
	int	  duration;
	int	  holdtime;
	int	  flags;

	if (isfadein == 1)
	{
		flags	 = (0x0002 | 0x0010);
		holdtime = RoundFloat(2000 * percent);
		duration = 10;
	}
	else
	{
		flags	 = (0x0001 | 0x0010);
		holdtime = RoundFloat(255 * percent);
		duration = holdtime;
	}
	int color[4]	= { 255, 255, 255, 255 };
	g_FadeUserMsgId = GetUserMessageId("Fade");
	Handle message	= StartMessageEx(g_FadeUserMsgId, clients, 1);
	if (GetUserMessageType() == UM_Protobuf)
	{
		Protobuf pb = UserMessageToProtobuf(message);
		pb.SetInt("duration", duration);
		pb.SetInt("hold_time", holdtime);
		pb.SetInt("flags", flags);
		pb.SetColor("clr", color);
	}
	else
	{
		BfWriteShort(message, duration);
		BfWriteShort(message, holdtime);
		BfWriteShort(message, flags);
		BfWriteByte(message, color[0]);
		BfWriteByte(message, color[1]);
		BfWriteByte(message, color[2]);
		BfWriteByte(message, color[3]);
	}
	EndMessage();
	delete dp;
}

void CreateMineDefuseButton(int iMineEnt)
{
	float pos[3];
	GetEntPropVector(iMineEnt, Prop_Data, "m_vecAbsOrigin", pos);
	pos[2] += 5.0;
	int iDefuseBtn = CreateEntityByName("func_button_timed");
	if (IsValidEntity(iDefuseBtn))
	{
		DispatchKeyValue(iDefuseBtn, "use_time", "3");
		DispatchKeyValue(iDefuseBtn, "use_string", "正在拆除地雷");
		DispatchKeyValue(iDefuseBtn, "use_sub_string", "");
		DispatchSpawn(iDefuseBtn);
		SetEntProp(iDefuseBtn, Prop_Send, "m_CollisionGroup", 1);
		SetEntityModel(iDefuseBtn, "");
		int Effect = GetEntProp(iDefuseBtn, Prop_Send, "m_fEffects");
		SetEntProp(iDefuseBtn, Prop_Send, "m_fEffects", Effect |= 32);
		SetEntPropEnt(iDefuseBtn, Prop_Send, "m_hOwnerEntity", iMineEnt);
		TeleportEntity(iDefuseBtn, pos, NULL_VECTOR, NULL_VECTOR);
		SDKHook(iDefuseBtn, SDKHook_Use, Use_CallBack);
		HookSingleEntityOutput(iDefuseBtn, "OnTimeUp", TimeUp_Callback);
		char sEnt[16];
		FormatEx(sEnt, 16, "%d", EntIndexToEntRef(iMineEnt));
		SetTrieValue(g_hMineTrine, sEnt, EntIndexToEntRef(iDefuseBtn));
	}
}

Action Use_CallBack(int entity, int activator, int caller, UseType type, float value)
{
	if (!IsClientInGhost(caller))
	{
		return Plugin_Handled;
	}
	int flags = GetEntityFlags(caller);
	if (!(flags & FL_ONGROUND))
	{
		return Plugin_Handled;
	}
	float pos[3];
	GetEntPropVector(entity, Prop_Data, "m_vecAbsOrigin", pos);
	PrecacheSound("weapons/hegrenade/beep.wav");
	EmitAmbientSound("weapons/hegrenade/beep.wav", pos, caller, .vol = 1.0);
	return Plugin_Continue;
}

void TimeUp_Callback(const char[] output, int caller, int activator, float delay)
{
	int mine = GetEntPropEnt(caller, Prop_Send, "m_hOwnerEntity");
	if (caller > 0) AcceptEntityInput(caller, "Kill");
	if (mine > 0) AcceptEntityInput(mine, "Kill");
	char sEnt[16];
	FormatEx(sEnt, 16, "%d", EntIndexToEntRef(mine));
	RemoveFromTrie(g_hMineTrine, sEnt);
}

// 减速弹相关, 减速判定持续5秒, 烟雾持续15秒

void CreateSmoke(float pos[3])
{
	int	 SmokeEnt = CreateEntityByName("env_smokestack");

	char originData[64];
	Format(originData, sizeof(originData), "%f %f %f", pos[0], pos[1], pos[2]);

	if (SmokeEnt)
	{
		// Create the Smoke
		DispatchKeyValue(SmokeEnt, "targetname", "Smoke");
		DispatchKeyValue(SmokeEnt, "Origin", originData);
		DispatchKeyValue(SmokeEnt, "BaseSpread", "100");
		DispatchKeyValue(SmokeEnt, "SpreadSpeed", "70");
		DispatchKeyValue(SmokeEnt, "Speed", "80");
		DispatchKeyValue(SmokeEnt, "StartSize", "300");
		DispatchKeyValue(SmokeEnt, "EndSize", "2");
		DispatchKeyValue(SmokeEnt, "Rate", "75");
		DispatchKeyValue(SmokeEnt, "JetLength", "400");
		DispatchKeyValue(SmokeEnt, "Twist", "20");
		DispatchKeyValue(SmokeEnt, "RenderColor", "255 255 255");	 // red green blue
		DispatchKeyValue(SmokeEnt, "RenderAmt", "255");
		DispatchKeyValue(SmokeEnt, "SmokeMaterial", "particle/particle_smokegrenade.vmt");

		DispatchSpawn(SmokeEnt);
		AcceptEntityInput(SmokeEnt, "TurnOn");

		// Start timer to stop smoke
		DataPack pack = new DataPack();
		CreateDataTimer(15.0, Timer_KillSmoke, pack);
		WritePackCell(pack, SmokeEnt);

		// Start timer to remove smoke
		DataPack pack2 = new DataPack();
		CreateDataTimer(20.0, Timer_StopSmoke, pack2);
		WritePackCell(pack2, SmokeEnt);
	}
}

Action Timer_KillSmoke(Handle timer, DataPack pack)
{
	pack.Reset();
	int SmokeEnt = ReadPackCell(pack);

	StopSmokeEnt(SmokeEnt);
}

void StopSmokeEnt(int target)
{
	if (IsValidEntity(target))
	{
		AcceptEntityInput(target, "TurnOff");
	}
}

Action Timer_StopSmoke(Handle timer, DataPack pack)
{
	pack.Reset();
	int SmokeEnt = ReadPackCell(pack);

	RemoveSmokeEnt(SmokeEnt);
}

void RemoveSmokeEnt(int target)
{
	if (target > 0 && IsValidEntity(target))
	{
		AcceptEntityInput(target, "Kill");
	}
}

public Action OnPlayerRunCmd(int client, int &buttons)
{
	if (!g_bGameStart)
	{
		return Plugin_Continue;
	}
	if (GetGameTime() > g_fUnfreezeTime[client])
	{
		return Plugin_Continue;
	}
	buttons |= IN_SPEED;
	return Plugin_Changed;
}

float GetEntityDistance(int ent1, int ent2)
{
	float vpos1[3];
	float vpos2[3];
	GetEntPropVector(ent1, Prop_Data, "m_vecAbsOrigin", vpos1);
	GetEntPropVector(ent2, Prop_Data, "m_vecAbsOrigin", vpos2);
	return GetVectorDistance(vpos1, vpos2);
}

//方法群
void GetClientFootOrigin(int client, float pos[3])
{
	float vAngles[3], fOrigin[3];
	GetClientEyePosition(client, fOrigin);
	GetClientEyeAngles(client, vAngles);
	vAngles[0]	 = 90.00;
	Handle trace = TR_TraceRayFilterEx(fOrigin, vAngles, MASK_SHOT, RayType_Infinite, TraceEntityFilterPlayer);
	if (TR_DidHit(trace))
	{
		TR_GetEndPosition(pos, trace);
	}
	CloseHandle(trace);
}
bool TraceEntityFilterPlayer(int entity, int contentsMask)
{
	char classname[128];
	GetEntityClassname(entity, classname, sizeof(classname));
	if (StrEqual(classname, "pipe_bomb_projectile"))
	{
		return false;
	}
	return entity > MaxClients;
}

void KillBtn(int mineEntity)
{
	int	 iDefuseBtnRef;
	char sEnt[16];
	FormatEx(sEnt, 16, "%d", EntIndexToEntRef(mineEntity));
	GetTrieValue(g_hMineTrine, sEnt, iDefuseBtnRef);
	int iDefuseBtn = EntRefToEntIndex(iDefuseBtnRef);
	if (iDefuseBtn > 0 && IsValidEntity(iDefuseBtn))
	{
		AcceptEntityInput(iDefuseBtn, "Disable");
		AcceptEntityInput(iDefuseBtn, "Kill");
	}
}