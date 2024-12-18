#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <colors>
#undef REQUIRE_PLUGIN
#include <left4dhooks>
#include <c4s2_ghost>

float g_fDamageCountInRound[MAXPLAYERS + 1];
bool  g_bPluginEnable;
int
	g_iKillCount[MAXPLAYERS + 1],
	g_iKillCountInRound[MAXPLAYERS + 1];

public Plugin myinfo =
{
	name		= "C4S2 Ghost - MVP System_T",
	author		= "Nepkey",
	description = "幽灵模式附加插件 - MVP播报_感染模式",
	version		= "1.2 - 2024.11.4",
	url			= "https://space.bilibili.com/436650372"
};

//---------------------------------------------------------------
//							基础设置
//---------------------------------------------------------------
public void OnPluginStart()
{
	RegServerCmd("sm_printgamemvp", PrintGameMvp);
	RegConsoleCmd("sm_mvp", PrintMVPToClient);
	HookEvent("player_disconnect", Disconnect_Event, EventHookMode_Pre);
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
	C4S2_OnGameover();
}

public void OnPlayerSpawn_Post(int client, bool gamestart)
{
	if (!g_bPluginEnable || !IsValidClientIndex(client) || !IsClientInGame(client))
	{
		return;
	}
}

public void OnPlayerHurt_Post(int victim, int attacker, float dmg)
{
	if (!g_bPluginEnable) return;
	if ((IsClientInSoilderEx(attacker) && IsClientInGhostEx(victim)) || (IsClientInSoilderEx(victim) && IsClientInGhostEx(attacker)))
	{
		g_fDamageCountInRound[attacker] += dmg;
	}
	if ((IsClientInSoilderEx(attacker) && IsClientInSoilderEx(victim)))
	{
		CPrintToChat(attacker, "{green}你对{blue}队友 %N {green}造成了 {blue}%d {green}点伤害。", victim, RoundFloat(dmg));
		CPrintToChat(victim, "{blue}队友 %N 对你造成了 {blue}%d {green}点伤害。", attacker, RoundFloat(dmg));
	}
}

public void OnPlayerKilled_Post(int victim, int attacker, const char[] weaponname, bool headshot, bool backstab)
{
	if (!g_bPluginEnable) return;
	if ((IsClientInSoilderEx(victim) && IsClientInSoilderEx(attacker)))
	{
		CPrintToChatAll("{blue}%N {green}误杀{blue} 队友 %N {green}。", attacker, victim);
		return;
	}
	else if (victim == attacker || !IsValidClientIndex(attacker))
	{
		CPrintToChatAll("{blue}%N {green}意外身亡。", victim);
		return;
	}
	g_iKillCountInRound[attacker] += 1;
	g_iKillCount[attacker] += 1;
	char info[512];
	Format(info, sizeof(info), "{green}%N {olive}击杀了 {green}%N, 获得 {blue}[point] {green}分。", attacker, victim);
	ReplaceString(info, sizeof(info), "[point]", "1");
	CPrintToChatAll(info);
}

public void C4S2Ghost_OnRoundStart_Post(bool gamestart)
{
	if (gamestart)
	{
		for (int i = 0; i <= MAXPLAYERS; i++)
		{
			g_iKillCountInRound[i]	 = 0;
			g_fDamageCountInRound[i] = 0.0;
		}
	}
}

public void C4S2Ghost_OnRoundEnd_Post()
{
	CreateTimer(0.5, PrintRoundData_Delay, _, TIMER_FLAG_NO_MAPCHANGE);
}

//此回调来自gamerule
public void C4S2_OnGameover()
{
}

//---------------------------------------------------------------
//							事件回调
//---------------------------------------------------------------

void Disconnect_Event(Event e, const char[] n, bool b)
{
	int client = GetClientOfUserId(e.GetInt("userid"));
	if (IsValidClientIndex(client) && !IsFakeClient(client))
	{
		g_iKillCountInRound[client]	  = 0;
		g_iKillCount[client]		  = 0;
		g_fDamageCountInRound[client] = 0.0;
	}
}

//---------------------------------------------------------------
//						回调函数+计时回调
//---------------------------------------------------------------

Action PrintRoundData_Delay(Handle timer)
{
	PrintRoundData(-1, true);
}

Action PrintGameMvp(int args)
{
	PrintGameMVPAll();
}
Action PrintMVPToClient(int client, int args)
{
	PrintRoundData(client, false);
}

Action WipeData_Delay(Handle timer)
{
	for (int i = 0; i < MAXPLAYERS; i++)
	{
		g_iKillCount[i]			 = 0;
		g_iKillCountInRound[i]	 = 0;
		g_fDamageCountInRound[i] = 0.0;
	}
}

//---------------------------------------------------------------
//							辅助方法
//---------------------------------------------------------------

void PrintRoundData(int caller, bool all)
{
	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsClientInGame(i) && (IsClientInGhostEx(i) || IsClientInSoilderEx(i)))
		{
			char info[250];
			Format(info, sizeof(info), "{blue}%s玩家 %N {default}- {green}总分数: {blue}%d {default}- {green}本回合分数: {blue}%d {default}- {green}有效伤害: {blue}%d", IsPlayerAlive(i) ? "[存活]" : "[死亡]", i, g_iKillCount[i], g_iKillCountInRound[i], RoundFloat(g_fDamageCountInRound[i]));
			if (all)
			{
				CPrintToChatAll(info);
			}
			else
			{
				CPrintToChat(caller, info);
			}
		}
	}
}

void PrintGameMVPAll()
{
	int survivor_index = -1;
	int survivor_clients[MAXPLAYERS + 1];
	for (int client = 1; client <= MaxClients; client++)
	{
		if (!IsClientInGame(client) || GetClientTeam(client) != 2) continue;
		survivor_index++;
		survivor_clients[survivor_index] = client;
	}
	SortCustom1D(survivor_clients, sizeof(survivor_clients), SortByScore);
	for (int i = 0; i < sizeof(survivor_clients); i++)
	{
		int client = survivor_clients[i];
		if (IsValidClientIndex(client) && IsClientInGame(client) && IsClientInGame(client))
		{
			CPrintToChatAll("{green}#%d {blue}%N {green}总分数：{blue}%d", i + 1, client, g_iKillCount[client]);
		}
	}
	CreateTimer(2.0, WipeData_Delay, _, TIMER_FLAG_NO_MAPCHANGE);
}

int SortByScore(int elem1, int elem2, const int[] array, Handle hndl)
{
	if (g_iKillCount[elem1] > g_iKillCount[elem2]) return -1;
	else if (g_iKillCount[elem2] > g_iKillCount[elem1]) return 1;
	else if (elem1 > elem2) return -1;
	else if (elem2 > elem1) return 1;
	return 0;
}

bool IsClientInGhostEx(int client)
{
	return C4S2Ghost_GetClientTeam(client) == 3;
}

bool IsClientInSoilderEx(int client)
{
	return C4S2Ghost_GetClientTeam(client) == 2;
}