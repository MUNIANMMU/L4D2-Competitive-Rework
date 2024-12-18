#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdkhooks>
#undef REQUIRE_PLUGIN
#include <left4dhooks>
#include <c4s2_ghost>

float	  g_fStealthEndTime;
char	  g_sHeartBeat[] = "player/heartbeatloop.wav";
ArrayList g_hGhostTeam_st;
bool
	g_bPluginEnable,
	g_bTotallyTtealth[MAXPLAYERS + 1],
	g_bSustainShow[MAXPLAYERS + 1],
	g_bOverThermal[MAXPLAYERS + 1],
	g_bIsRoundEnd;
ConVar
	g_hGhostStealth,
	g_hGhostBuff,
	g_hGhostRun,
	g_hHumanThermal;

float  g_fHumanThermal[MAXPLAYERS + 1];
int	   g_iHeartbeatType[MAXPLAYERS + 1];
Handle g_hBileBombTimer[MAXPLAYERS + 1] = { INVALID_HANDLE, ... };

public Plugin myinfo =
{
	name		= "C4S2 Ghost - Ghost Stealth",
	author		= "Nepkey",
	description = "幽灵模式附加插件 - 幽灵隐身模块/人类热力模块",
	version		= "1.3 - 2024.11.4",
	url			= "https://space.bilibili.com/436650372"
};

//---------------------------------------------------------------
//							基础设置
//---------------------------------------------------------------
public void OnPluginStart()
{
	g_hGhostTeam_st = new ArrayList();
	g_hGhostStealth = CreateConVar("c4s2_stealth_time", "300.0");
	g_hGhostBuff	= CreateConVar("c4s2_ghost_vampirism", "1");
	g_hGhostRun		= CreateConVar("c4s2_ghost_run_stealth", "1");
	g_hHumanThermal = CreateConVar("c4s2_ghost_human_thermal", "1");
	HookEvent("weapon_fire", Weapon_Fire_Event, EventHookMode_Pre);
}

public void OnAllPluginsLoaded()
{
	g_bPluginEnable = LibraryExists("c4s2_ghost");
}

public void OnLibraryAdded(const char[] name)
{
	if (StrEqual(name, "c4s2_ghost")) g_bPluginEnable = true;
}

public void OnLibraryRemoved(const char[] name)
{
	if (StrEqual(name, "c4s2_ghost")) g_bPluginEnable = false;
}

//---------------------------------------------------------------
//							全局转发
//---------------------------------------------------------------

//此转发来自grenade模块
public void OnGhostTouchMine(int victim, int attacker)
{
	g_bSustainShow[victim] = true;
	CreateTimer(1.5, Timer_RemoveShow, victim, TIMER_FLAG_NO_MAPCHANGE);
}

public void C4S2Ghost_OnRoundStart_Post(bool gamestart)
{
	if (!g_bPluginEnable) return;
	if (gamestart)
	{
		ClearThermal();
		g_bIsRoundEnd	  = false;
		g_fStealthEndTime = GetGameTime() + float(g_hGhostStealth.IntValue);
	}
}

public Action L4D_OnLedgeGrabbed(int client)
{
	if (!g_bPluginEnable) return Plugin_Continue;
	return Plugin_Handled;
}

public void OnPlayerKilled_Post(int victim, int attaker)
{
	if (!g_bPluginEnable) return;
	if (IsClientInGhost(attaker))
	{
		SetGhostBuff(attaker);
	}
	KillBileBombTimer(victim);
	AddHumanThermal(victim, -100.0);
}

public void OnClientPutInServer(int client)
{
	SDKHook(client, SDKHook_PostThinkPost, PostThinkPost_CallBack);
}

public void OnPlayerSpawn_Post(int client, bool gamestart)
{
	if (!g_bPluginEnable || !IsValidClientIndex(client) || !IsClientInGame(client))
	{
		return;
	}
	if (gamestart)
	{
		g_iHeartbeatType[client]  = 0;
		g_bTotallyTtealth[client] = false;
		g_bSustainShow[client]	  = false;
		if (IsClientInGhost(client))
		{
			L4D2_UseAdrenaline(client, g_fStealthEndTime - GetGameTime(), false, false);
			CreatePropGlow(client);
		}
		else if (IsClientInSoldier(client))
		{
			CreateTimer(0.25, Timer_ThermalHandle, client, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
		}
	}
}

public void C4S2Ghost_OnRoundEnd_Post()
{
	if (!g_bPluginEnable) return;
	for (int i = 0; i <= MAXPLAYERS; i++)
	{
		KillBileBombTimer(i);
	}
	g_bIsRoundEnd = true;
	g_hGhostTeam_st.Clear();
}

public void OnSoldierHitBySmoke(int client)
{
	ResetSoldierGlow(client);
	PrintHintText(client, "受减速弹的庇护，你的光圈会消失60秒。");
	KillBileBombTimer(client);
	g_hBileBombTimer[client] = CreateTimer(60.0, Timer_RestoreGlow, GetClientUserId(client), TIMER_FLAG_NO_MAPCHANGE);
}

public void OnMapStart()
{
	for (int i = 0; i <= MAXPLAYERS; i++)
	{
		g_hBileBombTimer[i] = INVALID_HANDLE;
	}
}

//---------------------------------------------------------------
//							回调函数
//---------------------------------------------------------------

void Weapon_Fire_Event(Event event, const char[] name, bool b)
{
	if (!g_bPluginEnable) return;
	char classname[128];
	int	 client = GetClientOfUserId(event.GetInt("userid"));
	event.GetString("weapon", classname, sizeof(classname));
	if (IsClientInGhost(client) && StrContains(classname, "melee") > -1)
	{
		SetGhostDebuff(client);
	}
	else if (IsClientInSoldier(client) && g_hHumanThermal.BoolValue)
	{
		float value;
		if (StrContains(classname, "shotgun") > -1)
		{
			value = 7.5;
		}
		else if (StrContains(classname, "ak47") > -1)
		{
			value = 2.5;
		}
		else if (StrContains(classname, "pistol") > -1)
		{
			value = 3.0;
		}
		else
		{
			value = 1.5;
		}
		AddHumanThermal(client, value);
	}
}

void PostThinkPost_CallBack(int client)
{
	if (!g_bPluginEnable) return;
	if (IsClientInGhost(client))
	{
		SetGhostHeartBeat(client);
		SetGhostStealth(client);
	}
	else if (IsClientInSoldier(client))
	{
		SetHumanState(client);
	}
}

Action OnTransmit(int iEntity, int iClient)
{
	if (!g_bPluginEnable) return Plugin_Continue;
	int iParent = GetEntPropEnt(iEntity, Prop_Send, "m_hOwnerEntity");
	if (!IsPlayerAlive(iParent))
	{
		SDKUnhook(iEntity, SDKHook_SetTransmit, OnTransmit);
		if (iEntity > 0) AcceptEntityInput(iEntity, "Kill");
		return Plugin_Handled;
	}
	if (IsClientInSoldier(iClient) || iParent == iClient)
	{
		return Plugin_Handled;
	}
	else
	{
		return Plugin_Continue;
	}
}

//---------------------------------------------------------------
//							计时回调
//---------------------------------------------------------------

Action Timer_RemoveTtealth(Handle Timer, int client)
{
	g_bTotallyTtealth[client] = false;
}

Action Timer_RemoveShow(Handle Timer, int client)
{
	g_bSustainShow[client] = false;
}

Action Timer_ThermalHandle(Handle timer, int client)
{
	if (!IsClientInSoldier(client) || !IsPlayerAlive(client) || g_bIsRoundEnd) return Plugin_Stop;
	if (!g_hHumanThermal.BoolValue) return Plugin_Continue;
	float baseMultiplier = 1.0;
	float baseCalmValue	 = 1.25;
	baseMultiplier *= TeamMateEffects(client);
	baseMultiplier *= g_bOverThermal[client] ? 1.5 : 1.0;
	baseCalmValue *= baseMultiplier;
	baseCalmValue *= SingleMoveMent(client) ? 3.0 : 1.0;

	AddHumanThermal(client, -baseCalmValue);
	PrintCenterText(client, "你的热力值:%.2f | %s", g_fHumanThermal[client], g_bOverThermal[client] ? "过热中" : "未过热");
	return Plugin_Continue;
}

Action Timer_RestoreGlow(Handle timer, int clientid)
{
	int client = GetClientOfUserId(clientid);
	if (IsValidClientIndex(client) && IsClientInGame(client) && IsPlayerAlive(client) && IsClientInSoldier(client))
	{
		SetSoldierGlow(client);
		PrintHintText(client, "你的光圈已恢复。");
	}
	g_hBileBombTimer[client] = INVALID_HANDLE;
}

//---------------------------------------------------------------
//							辅助方法
//---------------------------------------------------------------

void SetGhostBuff(int attacker)
{
	if (g_hGhostBuff.BoolValue)
	{
		int newhealth = GetClientHealth(attacker) + 50 >= 100 ? 100 : GetClientHealth(attacker) + 50;
		SetEntityHealth(attacker, newhealth);
	}
	g_bTotallyTtealth[attacker] = true;
	CreateTimer(3.0, Timer_RemoveTtealth, attacker, TIMER_FLAG_NO_MAPCHANGE);
}

void SetGhostDebuff(int attacker)
{
	g_bSustainShow[attacker] = true;
	CreateTimer(1.0, Timer_RemoveShow, attacker, TIMER_FLAG_NO_MAPCHANGE);
}

void CreatePropGlow(int iTarget)
{
	int iEntity = CreateEntityByName("prop_dynamic_override");
	if (iEntity == -1)
	{
		return;
	}

	float vOrigin[3];
	float vAngles[3] = { 90.0, 0.0, 0.0 };
	GetClientAbsOrigin(iTarget, vOrigin);
	vOrigin[2] += 7.5;
	TeleportEntity(iEntity, vOrigin, vAngles, NULL_VECTOR);
	char sModelName[PLATFORM_MAX_PATH];
	Format(sModelName, sizeof(sModelName), "models/props_collectables/coin.mdl");
	PrecacheModel(sModelName, true);
	SetEntityModel(iEntity, sModelName);
	DispatchKeyValue(iEntity, "targetname", "GlowEnt");
	DispatchSpawn(iEntity);

	SetEntProp(iEntity, Prop_Send, "m_CollisionGroup", 0);
	SetEntProp(iEntity, Prop_Send, "m_nSolidType", 0);
	SetEntProp(iEntity, Prop_Send, "m_nGlowRange", 5000);
	SetEntProp(iEntity, Prop_Send, "m_nGlowRangeMin", 0);
	SetEntProp(iEntity, Prop_Send, "m_iGlowType", 2);
	SetEntProp(iEntity, Prop_Send, "m_glowColorOverride", 65280);
	SetEntPropFloat(iEntity, Prop_Send, "m_flModelScale", 1.5);
	AcceptEntityInput(iEntity, "StartGlowing");
	SetEntityRenderMode(iEntity, RENDER_NONE);
	SetEntityRenderColor(iEntity, 0, 0, 0, 0);

	SetVariantString("!activator");
	AcceptEntityInput(iEntity, "SetParent", iTarget);
	SetVariantString("eyes");
	AcceptEntityInput(iEntity, "SetParentAttachmentMaintainOffset");

	SetEntPropEnt(iEntity, Prop_Send, "m_hOwnerEntity", iTarget);
	SDKHook(iEntity, SDKHook_SetTransmit, OnTransmit);
}

void SetGhostHeartBeat(int client)
{
	if (!g_hGhostRun.BoolValue) return;
	if (!IsClientInGame(client)) return;
	if (IsClientInSoldier(client)) return;
	if (IsClientInGhost(client))
	{
		float pos[3];
		GetClientAbsOrigin(client, pos);
		float vecSpeed[3];
		GetEntPropVector(client, Prop_Data, "m_vecVelocity", vecSpeed);
		float speed = GetVectorLength(vecSpeed);
		//重复三次停止播放，很蠢，但很有效果
		if (((!IsPlayerAlive(client)) || speed == 0) && g_iHeartbeatType[client] != 0)
		{
			g_iHeartbeatType[client] = 0;
			EmitAmbientSound(g_sHeartBeat, pos, client, SNDLEVEL_NORMAL, SND_STOPLOOPING, 0.0);
			EmitAmbientSound(g_sHeartBeat, pos, client, SNDLEVEL_NORMAL, SND_STOPLOOPING, 0.0);
			EmitAmbientSound(g_sHeartBeat, pos, client, SNDLEVEL_NORMAL, SND_STOPLOOPING, 0.0);
			return;
		}
		else if (0 < speed < 110 && (GetEntityFlags(client) & FL_ONGROUND) && ((GetClientButtons(client) & IN_SPEED) || (GetClientButtons(client) & IN_DUCK)))
		{
			if (g_iHeartbeatType[client] != 1)
			{
				g_iHeartbeatType[client] = 1;
				EmitAmbientSound(g_sHeartBeat, pos, client, SNDLEVEL_NORMAL, SND_STOPLOOPING, 0.0);
				EmitAmbientSound(g_sHeartBeat, pos, client, SNDLEVEL_NORMAL, SND_STOPLOOPING, 0.0);
				EmitAmbientSound(g_sHeartBeat, pos, client, SNDLEVEL_NORMAL, SND_STOPLOOPING, 0.0);
				EmitAmbientSound(g_sHeartBeat, pos, client, .vol = 0.2);
			}
			return;
		}
		else if (speed > 0 && IsPlayerAlive(client) && (GetEntityFlags(client) & FL_ONGROUND))
		{
			if (g_iHeartbeatType[client] != 2)
			{
				g_iHeartbeatType[client] = 2;
				EmitAmbientSound(g_sHeartBeat, pos, client, SNDLEVEL_NORMAL, SND_STOPLOOPING, 0.0);
				EmitAmbientSound(g_sHeartBeat, pos, client, SNDLEVEL_NORMAL, SND_STOPLOOPING, 0.0);
				EmitAmbientSound(g_sHeartBeat, pos, client, SNDLEVEL_NORMAL, SND_STOPLOOPING, 0.0);
				EmitAmbientSound(g_sHeartBeat, pos, client, .vol = 1.0);
			}
			return;
		}
	}
}

void SetGhostStealth(int client)
{
	if (!IsClientInGame(client)) return;
	if (IsClientInSoldier(client)) return;
	if (IsClientInGhost(client) && IsPlayerAlive(client))
	{
		SetEntityRenderMode(client, RENDER_TRANSALPHA);
		if (g_fStealthEndTime > GetGameTime())
		{
			int percent;
			if (g_bTotallyTtealth[client])
			{
				percent = 0;
			}
			else if (g_bSustainShow[client])
			{
				percent = 255;
			}
			else
			{
				percent = AlphaPersent(client);
			}
			SetGhostThirdStealth(client, percent);
			UpdateViewEffect(client, percent);
		}
		else
		{
			SetGhostThirdStealth(client, 255);
			UpdateViewEffect(client, 255);
		}
	}
}

void SetHumanState(int client)
{
	if (g_bOverThermal[client])
	{
		SetEntPropFloat(client, Prop_Send, "m_flNextAttack", GetGameTime() + 0.25);
	}
}

void AddHumanThermal(int client, float value)
{
	if (!g_hHumanThermal.BoolValue) return;
	g_fHumanThermal[client] += value;
	if (g_fHumanThermal[client] >= 100.0 && !g_bOverThermal[client])
	{
		g_fHumanThermal[client] = 100.0;
		PrintHintText(client, "你已进入过热状态, 过热解除前无法射击、");
		PrintToChatAll("\x03人类 %N \x04进入过热状态。在过热解除前其将无法射击, 且周围500单位的队友的过热衰减速率会降低20%%。", client);
		g_bOverThermal[client] = true;
	}
	else if (g_fHumanThermal[client] <= 0.0)
	{
		g_fHumanThermal[client] = 0.0;
		g_bOverThermal[client]	= false;
	}
}

void ClearThermal()
{
	for (int i = 0; i <= MaxClients; i++)
	{
		g_fHumanThermal[i] = 0.0;
		g_bOverThermal[i]  = false;
	}
}

float TeamMateEffects(int client)
{
	float baseMultiplier = 1.0;
	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsClientInSoldier(i) && g_bOverThermal[i] && i != client && GetClientsDistance(client, i) <= 500.0)
		{
			baseMultiplier *= 0.8;
		}
	}
	return baseMultiplier;
}

bool SingleMoveMent(int client)
{
	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsClientInSoldier(i) && IsPlayerAlive(i) && i != client && GetClientsDistance(client, i) <= 500.0)
		{
			return false;
		}
	}
	return true;
}

float GetClientsDistance(int clientA, int clientB)
{
	float Apos[3], Bpos[3];
	GetClientAbsOrigin(clientA, Apos);
	GetClientAbsOrigin(clientB, Bpos);
	return GetVectorDistance(Apos, Bpos);
}

//额外内容。使生还者始终处于冷静状态，便于听脚步。
/*
void SetSurvivorCalm(int client)
{
	if (!IsClientInGame(client)) return;
	if (IsClientInGhost(client)) return;
	if (IsClientInSoldier(client) && IsPlayerAlive(client))
	{
		SetEntProp(client, Prop_Send, "m_isCalm", 1);
	}
}
*/

int AlphaPersent(int client)
{
	float vecSpeed[3];
	GetEntPropVector(client, Prop_Data, "m_vecVelocity", vecSpeed);
	float speed = GetVectorLength(vecSpeed);
	if (speed <= 110 || (g_hGhostRun.BoolValue))
	{
		return 0;
	}
	else
	{
		return RoundFloat((speed / 260) * 255);
	}
}

void UpdateViewEffect(int client, int alpha)
{
	if (g_bSustainShow[client])
	{
		SetEntProp(client, Prop_Send, "m_bDrawViewmodel", 1);
	}
	else if (GetEntityFlags(client) & FL_ONGROUND)
	{
		SetEntProp(client, Prop_Send, "m_bDrawViewmodel", alpha > 1 ? 1 : 0);
	}
}

void SetGhostThirdStealth(int client, int alpha)
{
	int clientflags = GetEntProp(client, Prop_Send, "m_fEffects");
	int flagsshow	= clientflags & ~32;
	int flagshide	= clientflags | 32;
	if (g_bSustainShow[client])
	{
		SetEntityRenderColor(client, 255, 0, 0, 255);
		SetEntProp(client, Prop_Send, "m_fEffects", flagsshow);
	}
	else if (GetEntityFlags(client) & FL_ONGROUND)
	{
		SetEntityRenderColor(client, 255, 0, 0, alpha);
		SetEntProp(client, Prop_Send, "m_fEffects", alpha > 0 ? flagsshow : flagshide);
	}
	SetEntProp(client, Prop_Send, "m_iAddonBits", 0);
	int weapon = GetPlayerWeaponSlot(client, 1);
	if (IsValidEntity(weapon))
	{
		int flags = GetEntProp(weapon, Prop_Send, "m_fEffects");
		SetEntProp(weapon, Prop_Send, "m_fEffects", flags | 32);
	}
}

void KillBileBombTimer(int client)
{
	if (g_hBileBombTimer[client] != INVALID_HANDLE)
	{
		KillTimer(g_hBileBombTimer[client]);
	}
	g_hBileBombTimer[client] = INVALID_HANDLE;
}