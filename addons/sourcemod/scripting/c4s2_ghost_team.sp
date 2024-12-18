#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <colors>
#undef REQUIRE_PLUGIN
#include <left4dhooks>
#include <c4s2_ghost>

#include "simplevote.sp"

// int g_iObserveIndex[MAXPLAYERS + 1];
ConVar
	g_hMaxPlayer,
	g_hTransformMode,
	g_hFreezeTime,
	g_hGodTime;
bool
	g_bPluginEnable,
	g_bRoundStart,
	g_bAllowRespawnRepetitve;
ArrayList
	g_hAllPlayers,
	g_hRespawnPoints,
	g_hMapInfo;
enum struct MapCvar
{
	char mapname[128];
	int	 value;
}

public Plugin myinfo =
{
	name		= "C4S2 Ghost - Team Set",
	author		= "Nepkey",
	description = "幽灵模式附加插件 - 队伍设置模块。",
	version		= "1.2 - 2024.11.4",
	url			= "https://space.bilibili.com/436650372"
};

//---------------------------------------------------------------
//							基础设置
//---------------------------------------------------------------
public void OnPluginStart()
{
	g_hAllPlayers	 = new ArrayList();
	g_hRespawnPoints = new ArrayList();
	g_hMapInfo		 = new ArrayList(sizeof(MapCvar));

	RegConsoleCmd("sm_start", Callvote);
	RegConsoleCmd("sm_jg", JG_CMD);
	RegServerCmd("c4s2_respawn_repetitive", Repetitive_CMD);
	AddCommandListener(AFK_CMD, "go_away_from_keyboard");

	SetConVarInt(FindConVar("director_afk_timeout"), 999999);
	g_hMaxPlayer	 = CreateConVar("c4s2_ghost_max_players", "10");
	g_hTransformMode = CreateConVar("c4s2_ghost_transform", "0");
	g_hFreezeTime	 = CreateConVar("c4s2_ghost_freezetime", "3.0");
	g_hGodTime		 = CreateConVar("c4s2_ghost_godtime", "5.0");

	CreateTimer(1.0, DrawPlayersToPanel, _, TIMER_REPEAT);

	HookEvent("player_team", TeamEvent);
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
public void OnMapStart()
{
	g_bRoundStart = false;
	char mapname[128];
	GetCurrentMap(mapname, sizeof(mapname));
	int index = g_hMapInfo.FindString(mapname);
	if (index > -1)
	{
		MapCvar mc;
		g_hMapInfo.GetArray(index, mc);
		g_bAllowRespawnRepetitve = view_as<bool>(mc.value);
	}
	else
	{
		g_bAllowRespawnRepetitve = false;
	}
	PrintToServer("%s", g_bAllowRespawnRepetitve ? "地图已启用生还重复复活点" : "地图禁用重复复活点");
}

public void OnClientPutInServer(int client)
{
	if (!g_bPluginEnable) return;
	ClientCommand(client, "sm_jg");
	if (g_bRoundStart)
	{
		ForcePlayerSuicide(client);
	}
}

public void C4S2Ghost_OnRoundStart_Post(bool gamestart)
{
	if (!g_bPluginEnable) return;
	GetAllRespawnPoints();
	if (gamestart)
	{
		g_bRoundStart = gamestart;
		GroupPlayersIntoTeams();
		CreateTimer(0.5, Delay_SetAllClientFreezeOnStart, _, TIMER_FLAG_NO_MAPCHANGE);
	}
}

public void OnPlayerKilled_Pre(int victim)
{
	if (!g_bPluginEnable) return;
	if (g_hTransformMode.BoolValue)
	{
		PrintHintText(victim, "你将在5秒后复活并加入到对方阵营。");
		CreateTimer(5.0, RespawnNTransform, victim, TIMER_FLAG_NO_MAPCHANGE);
	}
}

public void OnPlayerSpawn_Post(int client, bool gamestart)
{
	if (!g_bPluginEnable || !IsValidClientIndex(client) || !IsClientInGame(client))
	{
		return;
	}
	if (gamestart)
	{
		if (IsFakeClient(client))
		{
			KickClient(client);
			return;
		}
		TeleportPlayerToStartPoint_Delay(client);
		SetClientInGod(client, g_hGodTime.FloatValue, true);
	}
}

public void C4S2_OnGameover()
{
	g_bRoundStart = false;
}

//---------------------------------------------------------------
//							回调函数
//---------------------------------------------------------------
/*
Action OverRide_ObserveTarget(int client, const char[] command, int argc)
{
	if (!g_bPluginEnable) return Plugin_Continue;
	if (IsPlayerAlive(client) || GetClientTeam(client) == 1 || !GetGameState())
	{
		return Plugin_Continue;
	}
	int team = C4S2Ghost_GetClientTeam(client);
	if (team == 3 && g_hGhosts.Length > 0)
	{
		if (g_iObserveIndex[client] >= g_hGhosts.Length)
		{
			g_iObserveIndex[client] = 0;
		}
		int	 target = g_hGhosts.Get(g_iObserveIndex[client]);
		char clientname[128];
		GetClientName(target, clientname, sizeof(clientname));
		FakeClientCommand(client, "spec_player \"%s\"", clientname);
		g_iObserveIndex[client]++;
	}
	else if (team == 2 && g_hSoldiers.Length > 0)
	{
		if (g_iObserveIndex[client] >= g_hSoldiers.Length)
		{
			g_iObserveIndex[client] = 0;
		}
		int	 target = g_hSoldiers.Get(g_iObserveIndex[client]);
		char clientname[128];
		GetClientName(target, clientname, sizeof(clientname));
		FakeClientCommand(client, "spec_player \"%s\"", clientname);
		g_iObserveIndex[client]++;
	}
	return Plugin_Handled;
}
*/
Action AFK_CMD(int client, const char[] command, int argc)
{
	if (!g_bPluginEnable) return Plugin_Continue;
	return Plugin_Handled;
}

Action JG_CMD(int client, int args)
{
	if (!g_bPluginEnable || !IsValidClientIndex(client)) return Plugin_Handled;
	if (C4S2Ghost_GetClientTeam(client) > 1) return Plugin_Handled;
	if (InvalidPlayers(2) + InvalidPlayers(3) >= g_hMaxPlayer.IntValue)
	{
		CPrintToChat(client, "{green}已达到游戏允许的人数上限。");
		return Plugin_Handled;
	}
	ChangeClientTeam(client, 2);
	if (g_bRoundStart && !g_hTransformMode.BoolValue)
	{
		ForcePlayerSuicide(client);
	}
	else
	{
		// 游戏开始前统一设置为人类
		C4S2Ghost_SetClientTeam(client, 2);
		if (g_bRoundStart && g_hTransformMode.BoolValue)
		{
			C4S2Ghost_SetClientTeam(client, GetRandomInt(2, 3));
		}
		L4D_RespawnPlayer(client);
	}
	return Plugin_Continue;
}

Action Repetitive_CMD(int args)
{
	if (args != 2)
	{
		PrintToServer("[SM] 用法: c4s2_respawn_repetitive <mapname> <int>");
	}
	MapCvar mc;
	GetCmdArg(1, mc.mapname, sizeof(mc.mapname));
	mc.value = GetCmdArgInt(2);
	g_hMapInfo.PushArray(mc);
}

Action Callvote(int iClient, int iArgs)
{
	if (!g_bPluginEnable) return Plugin_Handled;
	if (!GetGameState()) s_CallVote(iClient, "结束等待, 开始游戏?", GhostVote_Handler);
	return Plugin_Handled;
}

void GhostVote_Handler(Handle vote, int num_votes, int num_clients, const int[][] client_info, int num_items, const int[][] item_info)
{
	if (IsVotePass(vote, num_votes, num_clients, client_info, num_items, item_info))
	{
		SetGameState(true);
		L4D2_Rematch();
	}
}

int PlayersHudHandler(Menu hMenu, MenuAction action, int param1, int param2)
{
	return 1;
}

void TeamEvent(Event e, const char[] n, bool b)
{
	int client = GetClientOfUserId(e.GetInt("userid"));
	if (!IsFakeClient(client) && GetClientTeam(client) == 1) C4S2Ghost_SetClientTeam(client, 1, false);
}

//---------------------------------------------------------------
//							计时回调
//---------------------------------------------------------------

Action DrawPlayersToPanel(Handle timer)
{
	if (!g_bPluginEnable || GetGameState()) return Plugin_Continue;
	Panel g_hPanel = CreatePanel();
	SetPanelTitle(g_hPanel, "已加载到生还者队伍的玩家:", true);
	DrawPanelText(g_hPanel, "---------------------------------");
	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsClientInGame(i) && !IsFakeClient(i) && GetClientTeam(i) == 2)
		{
			char sname[128];
			GetClientName(i, sname, sizeof(sname));
			DrawPanelText(g_hPanel, sname);
		}
	}
	DrawPanelText(g_hPanel, "---------------------------------");
	DrawPanelText(g_hPanel, "人数足够后, 请用!start投票开始游戏。");
	DrawPanelText(g_hPanel, "要对游戏进行调整, 请用!gvote打开调整面板。");
	char info[250];
	Format(info, sizeof(info), "总人数不超过%d时, 可用!jg加入游戏。", g_hMaxPlayer.IntValue);
	DrawPanelText(g_hPanel, info);
	for (int i = 1; i <= MaxClients; i++)
	{
		if (BuiltinVote_IsVoteInProgress() && IsClientInBuiltinVotePool(i))
		{
			continue;
		}

		if (Game_IsVoteInProgress())
		{
			int voteteam = Game_GetVoteTeam();
			if (voteteam == -1 || voteteam == GetClientTeam(i))
			{
				continue;
			}
		}

		switch (GetClientMenu(i))
		{
			case MenuSource_External, MenuSource_Normal: continue;
		}
		if (IsClientInGame(i) && !IsFakeClient(i))
		{
			g_hPanel.Send(i, PlayersHudHandler, 1);
		}
	}
	delete g_hPanel;
	return Plugin_Continue;
}
/*
Action ObserverTargetFix(Handle timer, int client)
{
	if (!IsValidClientIndex(client) || !IsClientInGame(client) || IsPlayerAlive(client))
	{
		return Plugin_Stop;
	}
	int target = GetEntPropEnt(client, Prop_Send, "m_hObserverTarget");
	if (IsValidClientIndex(target) && IsClientInGame(target) && GetClientTeam(client) != 1)
	{
		if (C4S2Ghost_GetClientTeam(client) != C4S2Ghost_GetClientTeam(target))
		{
			FakeClientCommand(client, "spec_next");
		}
	}
	return Plugin_Continue;
}
*/
Action RespawnNTransform(Handle timer, int client)
{
	if (!g_bRoundStart) return Plugin_Stop;
	DataPack dp = new DataPack();
	dp.WriteCell(client);
	dp.WriteCell(C4S2Ghost_GetClientTeam(client) == 2 ? 3 : 2);
	if (!IsClientInGame(client)) return Plugin_Stop;
	L4D_RespawnPlayer(client);
	RequestFrame(ResetTeam, dp);
	return Plugin_Stop;
}

Action RemoveGod_Delay(Handle timer, int clientid)
{
	int client = GetClientOfUserId(clientid);
	if (!IsValidClientIndex(client) || !IsClientInGame(client)) return Plugin_Stop;
	int flag = GetEntityFlags(client);
	if (flag & FL_GODMODE)
	{
		flag &= ~FL_GODMODE;
		SetEntityFlags(client, flag);
	}
	return Plugin_Stop;
}

Action RemoveFreeze_Delay(Handle timer, int clientid)
{
	int client = GetClientOfUserId(clientid);
	if (!IsValidClientIndex(client) || !IsClientInGame(client)) return Plugin_Stop;
	int flag = GetEntityFlags(client);
	if (flag & FL_FROZEN)
	{
		flag &= ~FL_FROZEN;
		SetEntityFlags(client, flag);
	}
	SetEntProp(client, Prop_Send, "m_CollisionGroup", 5);
	return Plugin_Stop;
}

Action Delay_SetAllClientFreezeOnStart(Handle timer)
{
	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsClientInSoldier(i) || IsClientInGhost(i))
		{
			float fTime_2 = g_hFreezeTime.FloatValue;
			float fTime_3 = fTime_2 + 5.0;
			if (fTime_2 > 0.5)
			{
				PrintHintText(i, "你将在%.2f秒后允许行动。", C4S2Ghost_GetClientTeam(i) == 2 ? fTime_2 : fTime_3);
			}
			SetClientInFreeze(i, C4S2Ghost_GetClientTeam(i) == 2 ? fTime_2 : fTime_3, true);
		}
	}
}

//---------------------------------------------------------------
//							事件回调
//---------------------------------------------------------------

/*
void PlayerDeath_Event(Event e, const char[] n, bool b)
{
	int client = GetClientOfUserId(e.GetInt("userid"));
	if (IsValidClientIndex(client) && IsClientInGame(client))
	{
		CreateTimer(0.1, ObserverTargetFix, client, TIMER_REPEAT);
	}
}
*/

//---------------------------------------------------------------
//							辅助方法
//---------------------------------------------------------------

void GetAllRespawnPoints()
{
	g_hRespawnPoints.Clear();
	for (int i = MAXPLAYERS + 1; i < GetEntityCount(); i++)
	{
		if (!IsValidEntity(i))
		{
			continue;
		}
		char sname[64];
		GetEntPropString(i, Prop_Data, "m_iName", sname, sizeof(sname));
		if (StrContains(sname, "SpawnPoint") > -1)
		{
			g_hRespawnPoints.Push(i);
		}
	}
}

void GroupPlayersIntoTeams()
{
	g_hAllPlayers.Clear();

	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsClientInGame(i) && GetClientTeam(i) == 2 && !IsFakeClient(i))
		{
			g_hAllPlayers.Push(i);
		}
	}
	//游戏人数是奇数时，总是将多出来的一人移入幽灵队伍中。
	int ghosts = GetClientCountEx() > 1 ? RoundToFloor(GetClientCountEx() / 2 + 0.5) : 1;
	int ghostcount;
	//先抽取足够的幽灵
	while (ghostcount < ghosts && g_hAllPlayers.Length > 0)
	{
		int index  = GetRandomInt(0, g_hAllPlayers.Length - 1);
		int client = g_hAllPlayers.Get(index);
		if (IsFakeClient(client))
		{
			continue;
		}
		C4S2Ghost_SetClientTeam(client, 3);
		ghostcount++;
		g_hAllPlayers.Erase(index);
	}
	//剩余的玩家成为生还
	for (int i = 0; i < g_hAllPlayers.Length; i++)
	{
		int client = g_hAllPlayers.Get(i);
		C4S2Ghost_SetClientTeam(client, 2);
	}
}

stock int GetClientCountEx()
{
	int count;
	for (int i = 1; i <= MaxClients; i++)
	{
		count += IsClientInGame(i) && !IsFakeClient(i) && GetClientTeam(i) == 2 ? 1 : 0;
	}
	return count;
}

void TeleportPlayerToStartPoint_Delay(int client)
{
	if (g_hRespawnPoints.Length < 1)
	{
		CPrintToChatAll("{green}[!]检测到复活点位不足, 传送终止, 请管理员检查Stripper配置是否正确。");
		return;
	}
	int	  index = GetRandomInt(0, g_hRespawnPoints.Length - 1);
	int	  point = g_hRespawnPoints.Get(index);
	float pos[3];
	GetEntPropVector(point, Prop_Data, "m_vecAbsOrigin", pos);
	int nav = L4D_GetNearestNavArea(pos, 300.0, false, false, true);
	L4D_FindRandomSpot(nav, pos);
	TeleportEntity(client, pos, NULL_VECTOR, NULL_VECTOR);
	if (g_bAllowRespawnRepetitve && IsClientInSoldier(client)) return;
	if (!g_hTransformMode.BoolValue) g_hRespawnPoints.Erase(index);
}

int InvalidPlayers(int team)
{
	int count;
	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsClientInGame(i) || IsFakeClient(i) || GetClientTeam(i) != 2)
		{
			continue;
		}
		if (C4S2Ghost_GetClientTeam(i) == team)
		{
			count++;
		}
	}
	return count;
}

void SetClientInGod(int client, float releasetime, bool autorelease)
{
	int flag = GetEntityFlags(client);
	if (!(flag & FL_GODMODE))
	{
		flag |= FL_GODMODE;
		SetEntityFlags(client, flag);
		if (autorelease)
		{
			CreateTimer(releasetime, RemoveGod_Delay, GetClientUserId(client), TIMER_FLAG_NO_MAPCHANGE);
		}
	}
}

void SetClientInFreeze(int client, float releasetime, bool autorelease)
{
	int flag = GetEntityFlags(client);
	if (!(flag & FL_FROZEN))
	{
		flag |= FL_FROZEN;
		SetEntityFlags(client, flag);
		SetEntProp(client, Prop_Send, "m_CollisionGroup", 1);
		float zeroVec[3];
		TeleportEntity(client, NULL_VECTOR, NULL_VECTOR, zeroVec);
		if (autorelease)
		{
			CreateTimer(releasetime, RemoveFreeze_Delay, GetClientUserId(client), TIMER_FLAG_NO_MAPCHANGE);
		}
	}
}

void ResetTeam(DataPack dp)
{
	dp.Reset();
	int client = dp.ReadCell();
	int team   = dp.ReadCell();
	C4S2Ghost_SetClientTeam(client, team);
	delete dp;
}