#if defined _c4s2_included_
	#endinput
#endif
#define _c4s2_included_

#define HIDEHUD_VEHICLE_CROSSHAIR (1 << 9)

/**
 * 设置游戏状态。地图在加载的时候会重置为等待玩家状态。
 */
native void SetGameState(bool start);

/**
 * 查询游戏状态。
 * @return          处等待玩家状态时返回false, 否则为true。
 */
native bool GetGameState();

/**
 * 随机给予玩家一把主武器。
 */
native void GiveClientRandomWeapon(int client);

/**
 * 查询客户端进入服务器时的名字。
 * @param client        要查询的目标客户端id
 * @param buffer        储存字符串的容器
 * @param maxlength     字符串最大长度
 * @deprecated			因2.0修改光圈表现机制，已不再需要设置幽灵为空白名字，故不再使用。
 */
#pragma deprecated Do not use this function.
native void GetClientOriginalName(int client, const char[] buffer, int maxlength);

/**
 * 给定一个字符串参数, 从武器数据中匹配另一个参数。
 * @param searchin		给定的字符串参数
 * @param element		1 = weaponclassname, 5 = 短名, 其他参数暂不开放查询
 * @param buffer		储存字符串的容器
 * @param maxlength		容器长度
 */
native void GetWeaponData(const char[] searchin, int element, const char[] bufffer, int maxlength);

/**
 * 查询某名玩家是否属于幽灵阵营。
 * @param client        要查询的目标客户端id
 *
 * @return          如果是就返回true, 否则为false。
 */
native bool IsClientInGhost(int client);

/**
 * 查询某名玩家是否属于属于人类阵营。
 * @param client        要查询的目标客户端id
 *
 * @return          如果是就返回true, 否则为false。
 */
native bool IsClientInSoldier(int client);

/**
 * 查询某名玩家属于哪个阵营。
 * @param client        要查询的目标客户端id
 *
 * @return           返回0意味着不在服务器内, 1是旁观者, 2是人类, 3是幽灵。
 */
native int	C4S2Ghost_GetClientTeam(int client);

/**
 * 设置玩家阵营。
 * @param client        要修改的目标客户端id
 * @param team          目标阵营,3 = 幽灵，2 = 人类。
 * @param setglow		是否设置光圈
 *
 */
native void C4S2Ghost_SetClientTeam(int client, int team, bool setglow = true);

/**
 * 获取阵营成员。
 * @param team	要查询的目标阵营, 3 = 幽灵，2 = 人类
 * @param al	用于储存阵营成员userid的集合，如果仅查询人员数量，可以输入INVALID_HANDLE。
 * @param aliveonly 是否只获取存活的对象
 *
 * @return           阵营成员数量
 */
native int	C4S2Ghost_GetMemberList(int team, ArrayList al, bool aliveonly = false);

stock void	SetSoldierGlow(int client)
{
	SetEntProp(client, Prop_Send, "m_iGlowType", 3);
	SetEntProp(client, Prop_Send, "m_glowColorOverride", 11283500);
	SetEntProp(client, Prop_Send, "m_nGlowRange", 0);
	SetEntProp(client, Prop_Send, "m_nGlowRangeMin", 0);
	SetEntProp(client, Prop_Send, "m_bFlashing", 0);
}

stock void ResetSoldierGlow(int client)
{
	SetEntProp(client, Prop_Send, "m_iGlowType", 0);
	SetEntProp(client, Prop_Send, "m_glowColorOverride", 0);
	SetEntProp(client, Prop_Send, "m_nGlowRange", 0);
	SetEntProp(client, Prop_Send, "m_nGlowRangeMin", 0);
	SetEntProp(client, Prop_Send, "m_bFlashing", 0);
}

// Author - A1m`
stock bool IsValidClientIndex(int client)
{
	return (client > 0 && client <= MaxClients);
}

/**
 * 游戏回合开始后调用。由事件round_start转发得来，但拥有首回合加载判定。
 * @param gamestart	    如果游戏可以开始, 为true;等待其他玩家加载中, 为false。
 *
 */
forward void   C4S2Ghost_OnRoundStart_Post(bool gamestart);

/**
 * 游戏回合结束后调用。唯一触发条件是任意一方团灭。
 * @param wonteam       2 = 生还胜利, 3=幽灵胜利。
 * @param info          附加报文。可选择用PrintToChatAll或其他途径播报。
 */
forward void   C4S2Ghost_OnRoundEnd_Post(int wonteam, const char[] info);

/**
 * 玩家重生之后调用。为避免冲突, 该转发具有0.3秒的延迟。
 * @param client        客户端id
 * @param gamestart        游戏是否开始
 *
 */
forward void   OnPlayerSpawn_Post(int client, bool gamestart);

/**
 * 当玩家被杀死前调用。自杀事件不会被转发。通常用于修正死亡音效不触发。
 *
 * @param victim        死者id
 * @param attacker      攻击者id
 * @param weaponname    武器名字
 * @param headshot      是否爆头
 * @param backstab      是否背刺
 */
forward void   OnPlayerKilled_Pre(int victim, int attacker, const char[] weaponname, bool headshot, bool backstab);

/**
 * 当玩家被杀死后调用。自杀事件不会被转发。
 *
 * @param victim        死者id
 * @param attacker      攻击者id
 * @param weaponname    武器名字
 * @param headshot      是否爆头
 * @param backstab      是否背刺
 */
forward void   OnPlayerKilled_Post(int victim, int attacker, const char[] weaponname, bool headshot, bool backstab);

/**
 * 玩家"受伤"之后调用。这并不是通常意义上的受伤,而是在产生攻击判定时,
 * 经由插件削减血量模拟出的受伤效果。如果在Pre中阻止后续，Post将不会被触发。
 * @param victim        受击者id
 * @param attacker      攻击者id
 * @param damage        伤害值
 */
forward void   OnPlayerHurt_Post(int victim, int attacker, float damage);

/**
 * 玩家"受伤"之前调用。这并不是通常意义上的受伤,而是在产生攻击判定时,
 * 经由插件削减血量模拟出的受伤效果。
 * @param victim        受击者id
 * @param attacker      攻击者id
 * @param damage        伤害值
 *
 * @return          Plugin_Handle将终止伤害计算, Plugin_Continue将允许伤害计算。
 */
forward Action OnPlayerHurt_Pre(int victim, int attacker, float damage);

public SharedPlugin __pl_c4s2_ghost = {
	name = "c4s2_ghost",
	file = "c4s2_ghost.smx",
#if defined REQUIRE_PLUGIN
	required = 1,
#else
	required = 0,
#endif
};

#if !defined REQUIRE_PLUGIN

public void __pl_c4s2_ghost_SetNTVOptional()
{
	MarkNativeAsOptional("SetGameState");
	MarkNativeAsOptional("GetGameState");
	MarkNativeAsOptional("GiveClientRandomWeapon");
	MarkNativeAsOptional("GetClientOriginalName");
	MarkNativeAsOptional("GetWeaponData");
	MarkNativeAsOptional("IsClientInGhost");
	MarkNativeAsOptional("IsClientInSoldier");
	MarkNativeAsOptional("C4S2Ghost_GetClientTeam");
	MarkNativeAsOptional("C4S2Ghost_SetClientTeam");
	MarkNativeAsOptional("C4S2Ghost_GetMemberList");
}
#endif