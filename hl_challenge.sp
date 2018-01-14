/*  [Multi-1v1] Challenge Plugin - The easiest way to piss off your friend
 *
 *  Copyright (C) 2016 Michael Flaherty // michaelwflaherty.com // michaelwflaherty@me.com
 * 
 * This program is free software: you can redistribute it and/or modify it
 * under the terms of the GNU General Public License as published by the Free
 * Software Foundation, either version 3 of the License, or (at your option) 
 * any later version.
 *
 * This program is distributed in the hope that it will be useful, but WITHOUT 
 * ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS 
 * FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License along with 
 * this program. If not, see http://www.gnu.org/licenses/.
 */
 
#include <sourcemod>
#include <clientprefs>
#include <autoexecconfig>
#include <hl_challenge>
#include <cstrike>
#include <store>

#define REQUIRE_PLUGIN
#include <multi1v1>

#pragma semicolon 1
#pragma newdecls required

#define PLUGIN_VERSION "1.1.5"
//#define DEBUG

/* Handles */
Handle g_hOnRankingQueueBuilt = null;
Handle g_hOnChallengeWon = null;
Handle g_hClientCookie = null;

/* ArrayLists :D */
ArrayList challengeQueue;

/* ConVars */ 
ConVar gcv_bPluginEnabled = null;
ConVar gcv_iCooldown = null;
ConVar gcv_iBetMultiplier = null;
ConVar gcv_bBlockRatingChanges = null;
ConVar gcv_bSaveOldArena = null;
ConVar gcv_iRequestCooldown = null;
ConVar gcv_bChallengePref = null;

/* Booleans */
bool ga_bChallengePref[MAXPLAYERS + 1] = {true, ...};
bool ga_bIsInChallenge[MAXPLAYERS + 1] = {false, ...};
bool g_bLateLoad;
bool g_bZephrusStore = false;

/* Integers */
int ga_iCooldown[MAXPLAYERS + 1] = {0, ...};
int ga_iBetAmount[MAXPLAYERS + 1] = {0, ...};
int ga_iOldArena[MAXPLAYERS + 1] = {-1, ...};
int ga_iLastRequest[MAXPLAYERS + 1] = {0, ...};

public Plugin myinfo =
{
	name = "[Multi-1v1] Challenge",
	author = "Headline",
	description = "A simple challlenge plugin for Splewis' Multi-1v1 Style servers!",
	version = PLUGIN_VERSION,
	url = "http://www.michaelwflaherty.com"
}

/******************************************************************
**************************** NATIVES ******************************
******************************************************************/

public APLRes AskPluginLoad2(Handle hMyself, bool bLate, char[] sError, int err_max)
{
	MarkNativeAsOptional("Store_GetClientCredits");
	MarkNativeAsOptional("Store_SetClientCredits");
	
	g_bLateLoad = bLate;
	
	CreateNative("hl_isInChallenge", Native_IsInChallenge);
	CreateNative("hl_isInChallengeQueue", Native_IsInChallengeQueue);
	CreateNative("hl_getChallengePartner", Native_GetChallengePartner);
	CreateNative("hl_placeInChallengeQueue", Native_PlaceInChallengeQueue);
	
	RegPluginLibrary("hl_challenge");
	
	return APLRes_Success;
}

public int Native_IsInChallenge(Handle plugin, int iNumParams)
{
	int client = GetNativeCell(1);
	
	if (!IsValidClient(client))
	{
		return ThrowNativeError(SP_ERROR_NATIVE, "Invalid client index (%i)", client);
	}
	else
	{
		return ga_bIsInChallenge[client];
	}
}

public int Native_IsInChallengeQueue(Handle plugin, int iNumParams)
{
	int client = GetNativeCell(1);
	
	if (!IsValidClient(client))
	{
		return ThrowNativeError(SP_ERROR_NATIVE, "Invalid client index (%i)", client);
	}
	else
	{
		return isInChallengeQueue(client);
	}
}

public int Native_GetChallengePartner(Handle plugin, int iNumParams)
{
	int client = GetNativeCell(1);

	if (!IsValidClient(client))
	{
		return ThrowNativeError(SP_ERROR_NATIVE, "Invalid client index (%i)", client);
	}
	else
	{
		return getClientParter(client);
	}
}

public int Native_PlaceInChallengeQueue(Handle plugin, int iNumParams)
{
	int client1 = GetNativeCell(1);
	int client2 = GetNativeCell(1);

	if (!IsValidClient(client1))
	{
		return ThrowNativeError(SP_ERROR_NATIVE, "Invalid client index (%i)", client1);
	}
	else if (!IsValidClient(client2))
	{
		return ThrowNativeError(SP_ERROR_NATIVE, "Invalid client index (%i)", client2);
	}
	else
	{
		placeInChallengeQueue(client1, client2);
		return 0;
	}
}

void onRankingQueueBuilt(ArrayList rankingQueue)
{	
	Call_StartForward(g_hOnRankingQueueBuilt);
	Call_PushCell(rankingQueue);
	Call_Finish();
}

void onChallengeWon(int winner, int loser)
{
	Call_StartForward(g_hOnChallengeWon);
	Call_PushCell(winner);
	Call_PushCell(loser);
	Call_Finish();
}

public void OnAllPluginsLoaded()
{
	g_bZephrusStore = LibraryExists("store_zephyrus");
}

public void OnLibraryAdded(const char[] library)
{
	if (StrEqual(library, "store_zephyrus"))
	{
		g_bZephrusStore = true;
	}
}

public void OnLibraryRemoved(const char[] library)
{
	if (StrEqual(library, "store_zephyrus"))
	{
		g_bZephrusStore = false;
	}
}
/******************************************************************
**************************** PLUGIN *******************************
******************************************************************/


public void OnPluginStart()
{
	/* Load Translation File for FindTarget */
	LoadTranslations("common.phrases.txt");

	/* Commands */
	RegConsoleCmd("sm_challenge", Command_Challenge, "Allows users to challenge their friends!");
	RegConsoleCmd("sm_chal", Command_Challenge, "Allows users to challenge their friends!");
	
	/* Events */
	HookEvent("player_disconnect", Event_PlayerDisconnect);
	
	/* Forwards */
	g_hOnRankingQueueBuilt = CreateGlobalForward("hl_onRankingQueueBuilt", ET_Ignore, Param_Cell);
	g_hOnChallengeWon = CreateGlobalForward("hl_onChallengeWon", ET_Ignore, Param_Cell, Param_Cell);

	/* ConVars */
	AutoExecConfig_SetFile("hl_challenge");
	AutoExecConfig_CreateConVar("hl_challenge_version", PLUGIN_VERSION, "Headline's Challenge Plugin Version", FCVAR_DONTRECORD);

	gcv_bPluginEnabled = AutoExecConfig_CreateConVar("hl_challenge_enabled", "1", "Determines whether or not the plugin is enabled", _, true, 0.0, true, 1.0);
	gcv_iCooldown = AutoExecConfig_CreateConVar("hl_challenge_cooldown", "3", "Determines how many rounds the player must wait until they can challenge again.\nSet 0 to disable", _, true, 0.0, true, 10.0);
	gcv_bBlockRatingChanges = AutoExecConfig_CreateConVar("hl_challenge_ratingchanges", "1", "Determines if challenge outcomes affect Multi-1v1 ratings\nSet 1 to allow rating changes", _, true, 0.0, true, 1.0);
	gcv_bSaveOldArena = AutoExecConfig_CreateConVar("hl_challenge_saveoldarenas", "1", "When a player joins a challenge, their old arena is saved so\nthey will be placed back when the round ends", _, true, 0.0, true, 1.0);
	gcv_iBetMultiplier = AutoExecConfig_CreateConVar("hl_challenge_betmultiplier", "15", "Determines the multiplicity by which the bet amount is generated", _, true, 5.0);
	gcv_iRequestCooldown = AutoExecConfig_CreateConVar("hl_challenge_requestcooldown", "30", "Sets the time a player must wait in between requests (seconds)", _, true, 5.0);
	gcv_bChallengePref = AutoExecConfig_CreateConVar("hl_challenge_preference", "1", "Allows users to turn off challenges so they will not receive or be able to send challenge requests", _, true, 0.0, true, 10.0);
	
	AutoExecConfig_ExecuteFile();
	AutoExecConfig_CleanFile();

	/* Cookies */
	g_hClientCookie = RegClientCookie("multi1v1-challenge", "Cookie to client challenge preference", CookieAccess_Public);

	/* Reset Client Vars */
	if (g_bLateLoad)
	{
		for (int i = 0; i < MaxClients; i++)
		{
			if (IsValidClient(i))
			{
				OnClientConnected(i);
				
				if (AreClientCookiesCached(i))
				{
					OnClientCookiesCached(i);
				}
			}
		}
	}
}


public void OnMapStart()
{
	challengeQueue = new ArrayList();
}

public void OnClientConnected(int client)
{
	ga_bChallengePref[client] = true;
	ga_bIsInChallenge[client] = false;
	ga_iCooldown[client] = 0;
	ga_iBetAmount[client] = 0;
	ga_iOldArena[client] = -1;
}

public void OnClientCookiesCached(int client)
{
	if(gcv_bPluginEnabled.BoolValue && gcv_bChallengePref.BoolValue)
	{
		LoadCookies(client);
	}
}

public void OnClientDisconnect(int client)
{
	SaveCookies(client);
	
	ga_bChallengePref[client] = true;
	ga_bIsInChallenge[client] = false;
	ga_iCooldown[client] = 0;
	ga_iBetAmount[client] = 0;
	ga_iOldArena[client] = -1;
}

public Action Event_PlayerDisconnect(Event hEvent, const char[] sName, bool bDontBroadcast)
{
	int client = GetClientOfUserId(hEvent.GetInt("userid"));
	int partner;
	if (isInChallengeQueue(client))
	{
		partner = removePairFromQueue(client);
	}
	else if (ga_bIsInChallenge[client])
	{
		partner = getClientParter(client);
		if (!IsValidClient(partner))
		{
			return;
		}
		int betAmount = ga_iBetAmount[partner];

		ga_bIsInChallenge[client] = false;
		ga_bIsInChallenge[partner] = false;
		
		if (g_bZephrusStore && betAmount > 0)
		{
			int credits;
			Multi1v1_MessageToAll(" \x03%N\x01 has beaten \x03%N\x01 in a challenge over \x03%i\x01 credits!", partner, client, betAmount);
			
			credits = Store_GetClientCredits(client);
			Store_SetClientCredits(client, credits - betAmount);
			credits = Store_GetClientCredits(partner);
			Store_SetClientCredits(partner, credits + betAmount);
		}
		else
		{
			Multi1v1_MessageToAll(" \x03%N\x01 has beaten \x03%N\x01 in a challenge !", partner, client);
		}

		
		onChallengeWon(partner, client);
	}
}

/******************************************************************
************************ USER INPUT *******************************
*******************************************************************/


public void Multi1v1_OnGunsMenuCreated(int client, Menu menu)
{
	if (!gcv_bChallengePref.BoolValue)
	{
		return;
	}
	
	if (ga_bChallengePref[client])
	{
		AddMenuItem(menu, "challenge", "Challenges: enabled");
	}
	else
	{
		AddMenuItem(menu, "challenge", "Challenges: disabled");
	}
}

public void Multi1v1_GunsMenuCallback(Menu menu, MenuAction action, int param1, int param2)
{
	if (!gcv_bChallengePref.BoolValue)
	{
		return;
	}
	switch (action)
	{
		case MenuAction_Select:
		{
			char sInfo[128];
			GetMenuItem(menu, param2, sInfo, sizeof(sInfo));
			if (StrEqual(sInfo, "challenge"))
			{
				if (ga_bChallengePref[param1])
				{
					ga_bChallengePref[param1] = false;
					SaveCookies(param1);
					
					Multi1v1_Message(param1, "You have successfully disabled challenges!");
				}
				else
				{
					ga_bChallengePref[param1] = true;
					SaveCookies(param1);
					Multi1v1_Message(param1, "You have successfully enabled challenges!");
				}
			}
			Multi1v1_GiveWeaponsMenu(param1, GetMenuSelectionPosition());
		}
		case MenuAction_End:
		{
			delete menu;
		}
	}
}

public Action Command_Challenge(int client, int args)
{
	if (!IsValidClient(client, true))
	{
		Multi1v1_Message(client, "You must be in-game to use this command!");
		return Plugin_Handled;
	}
	if (ga_bIsInChallenge[client])
	{
		Multi1v1_Message(client, "You are already in a challenge!");
		return Plugin_Handled;
	}
	if (isInChallengeQueue(client))
	{
		Multi1v1_Message(client, "You are already in a queue for a challenge!");
		return Plugin_Handled;
	}
	if (ga_iCooldown[client] > 0)
	{
		Multi1v1_Message(client, "You must wait %i more rounds to challenge again!", ga_iCooldown[client]);
		return Plugin_Handled;
	}
	if (!gcv_bPluginEnabled.BoolValue)
	{
		Multi1v1_Message(client, "This plugin is currently disabled!");
		return Plugin_Handled;
	}
	if ((ga_iLastRequest[client] + gcv_iRequestCooldown.IntValue) > GetTime())
	{
		Multi1v1_Message(client, "You must wait %i more seconds to challenge again!", (ga_iLastRequest[client] + gcv_iRequestCooldown.IntValue) - GetTime());
		return Plugin_Handled;
	}
	if (gcv_bChallengePref.BoolValue)
	{
		if (!ga_bChallengePref[client])
		{
			Multi1v1_Message(client, "You must first enable challenges in the guns menu!");
			return Plugin_Handled;
		}
	}
	if (GetClientTeam(client) == CS_TEAM_SPECTATOR)
	{
		Multi1v1_Message(client, "You may not challenge as a spectator!");
		return Plugin_Handled;
	}
	
	if (args == 1)
	{
		char sArg1[MAX_TARGET_LENGTH];
		GetCmdArg(1, sArg1, sizeof(sArg1));
		int target = FindTarget(client, sArg1, true, false);
		if (IsValidClient(target, true))
		{
			if (target != client)
			{
				if (ga_bIsInChallenge[target])
				{
					Multi1v1_Message(client, "They are already in a challenge!");
					return Plugin_Handled;
				}
				if (isInChallengeQueue(target))
				{
					Multi1v1_Message(client, "They are already in a queue for a challenge!");
					return Plugin_Handled;
				}
				if (ga_iCooldown[target] > 0)
				{
					Multi1v1_Message(client, "They must wait %i more rounds to challenge again!", ga_iCooldown[target]);
					return Plugin_Handled;
				}
				if (gcv_bChallengePref.BoolValue)
				{
					if (!ga_bChallengePref[target])
					{
						Multi1v1_Message(client, "They must first enable challenges in the guns menu!");
						return Plugin_Handled;
					}
				}
				if (GetClientTeam(target) == CS_TEAM_SPECTATOR)
				{
					Multi1v1_Message(target, "They may not challenge as a spectator!");
					return Plugin_Handled;
				}

				OpenRequestMenu(target, client, 0);
			}
			else
			{
				Multi1v1_Message(client, "You cannot target yourself!");
			}
		}
	}
	else if (args == 0)
	{
		OpenChallengeMenu(client);
	}
	else
	{
		Multi1v1_Message(client, "Usage: sm_challenge");
		return Plugin_Handled;
	}
	return Plugin_Handled;
}

void OpenChallengeMenu(int client) 
{ 
	char sDisplayBuffer[128], sInfoBuffer[16], sTitle[64];
	int count = 0;
	Format(sTitle, sizeof(sTitle), "Select a Player :");
	
	Menu MainMenu = new Menu(MainMenu_CallBack, MenuAction_Select | MenuAction_End); 
	MainMenu.SetTitle(sTitle); 
	
	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsValidClient(i, false, true) && i != client)
		{
			count++;
			Format(sDisplayBuffer, sizeof(sDisplayBuffer), "%N", i);
			Format(sInfoBuffer, sizeof(sInfoBuffer), "%i", GetClientUserId(i));
			MainMenu.AddItem(sInfoBuffer, sDisplayBuffer);
		}
	}
	
	if (count == 0)
	{
		Multi1v1_Message(client, "There are no players to challenge!");
		return;
	}
	
	DisplayMenu(MainMenu, client, MENU_TIME_FOREVER); 
}

public int MainMenu_CallBack(Menu MainMenu, MenuAction action, int param1, int param2) 
{
	switch (action)
	{
		case MenuAction_Select:
		{
			if (!IsValidClient(param1))
			{
				return;
			}
			char sInfo[128];
			GetMenuItem(MainMenu, param2, sInfo, sizeof(sInfo));
			
			int target = GetClientOfUserId(StringToInt(sInfo));
			if (!IsValidClient(target))
			{
				return;
			}
			
			if (ga_bIsInChallenge[target])
			{
				Multi1v1_Message(param1, "They are already in a challenge!");
				return;
			}
			if (isInChallengeQueue(target))
			{
				Multi1v1_Message(param1, "They are already in a queue for a challenge!");
				return;
			}
			if (ga_iCooldown[target] > 0)
			{
				Multi1v1_Message(param1, "They must wait %i more rounds to challenge again!", ga_iCooldown[target]);
				return;
			}
			if (gcv_bChallengePref.BoolValue)
			{
				if (!ga_bChallengePref[target])
				{
					Multi1v1_Message(param1, "They must first enable challenges in the guns menu!");
					return;
				}
			}
			if (GetClientTeam(target) == CS_TEAM_SPECTATOR)
			{
				Multi1v1_Message(target, "They may not challenge as a spectator!");
				return;
			}

			
			if (ga_bIsInChallenge[param1])
			{
				Multi1v1_Message(param1, "You are already in a challenge!");
				return;
			}
			if (isInChallengeQueue(param1))
			{
				Multi1v1_Message(param1, "You are already in a queue for a challenge!");
				return;
			}
			if (ga_iCooldown[param1] > 0)
			{
				Multi1v1_Message(param1, "You must wait %i more rounds to challenge again!", ga_iCooldown[param1]);
				return;
			}
			if (gcv_bChallengePref.BoolValue)
			{
				if (!ga_bChallengePref[param1])
				{
					Multi1v1_Message(param1, "You must first enable challenges in the guns menu!");
					return;
				}
			}
			if (GetClientTeam(param1) == CS_TEAM_SPECTATOR)
			{
				Multi1v1_Message(param1, "You may not challenge as a spectator!");
				return;
			}

			if (g_bZephrusStore)
			{
				OpenBetSelectionMenu(param1, target);
			}
			else
			{
				OpenRequestMenu(target, param1, 0);
			}
		}
		case MenuAction_End:
		{
			delete MainMenu;
		}
	}
}

void OpenBetSelectionMenu(int client, int target) 
{
	char sInfoBuffer[128], sTitle[128], sDisplayBuffer[128];
	
	Format(sTitle, sizeof(sTitle), "Select Credit Amount To Bet!");
	
	Menu MainMenu = new Menu(CreditMenu_Callback, MenuAction_Select | MenuAction_End); 
	MainMenu.SetTitle(sTitle); 
	
	Format(sInfoBuffer, sizeof(sInfoBuffer), "0;%i", GetClientUserId(target));
	MainMenu.AddItem(sInfoBuffer, "None");

	for (int i = 1; i <= 5; i++)
	{
		Format(sInfoBuffer, sizeof(sInfoBuffer), "%i;%i", (i*gcv_iBetMultiplier.IntValue),GetClientUserId(target));
		Format(sDisplayBuffer, sizeof(sDisplayBuffer), "%i Credits", (i*gcv_iBetMultiplier.IntValue));
		MainMenu.AddItem(sInfoBuffer, sDisplayBuffer, (isValidBetAmount(client, target, (i*gcv_iBetMultiplier.IntValue)))?ITEMDRAW_DEFAULT:ITEMDRAW_DISABLED);
	}
	
	DisplayMenu(MainMenu, client, 15); 
}


public int CreditMenu_Callback(Menu MainMenu, MenuAction action, int param1, int param2) 
{
	switch (action)
	{
		case MenuAction_Select:
		{
			char sInfo[128], sTempArray[2][128];
			GetMenuItem(MainMenu, param2, sInfo, sizeof(sInfo));
			ExplodeString(sInfo, ";", sTempArray, 2, sizeof(sTempArray[]));
			int credits = StringToInt(sTempArray[0]);
			
			int target = GetClientOfUserId(StringToInt(sTempArray[1]));
			if (!IsValidClient(target))
			{
				return;
			}
			
			if (!isValidBetAmount(param1, target, credits))
			{
				OpenBetSelectionMenu(param1, target);
				Multi1v1_Message(param1, "You or your target do not have sufficent credits!");
				return;
			}
			
			if (ga_bIsInChallenge[target])
			{
				Multi1v1_Message(param1, "They are already in a challenge!");
				return;
			}
			if (isInChallengeQueue(target))
			{
				Multi1v1_Message(param1, "They are already in a queue for a challenge!");
				return;
			}
			if (ga_iCooldown[target] > 0)
			{
				Multi1v1_Message(param1, "They must wait %i more rounds to challenge again!", ga_iCooldown[target]);
				return;
			}
			if (GetClientTeam(target) == CS_TEAM_SPECTATOR)
			{
				Multi1v1_Message(target, "They may not challenge as a spectator!");
				return;
			}

			
			if (ga_bIsInChallenge[param1])
			{
				Multi1v1_Message(param1, "You are already in a challenge!");
				return;
			}
			if (isInChallengeQueue(param1))
			{
				Multi1v1_Message(param1, "You are already in a queue for a challenge!");
				return;
			}
			if (ga_iCooldown[param1] > 0)
			{
				Multi1v1_Message(param1, "You must wait %i more rounds to challenge again!", ga_iCooldown[param1]);
				return;
			}
			if (GetClientTeam(param1) == CS_TEAM_SPECTATOR)
			{
				Multi1v1_Message(param1, "You may not challenge as a spectator!");
				return;
			}

			OpenRequestMenu(target, param1, credits);
			
		}
		case MenuAction_End:
		{
			delete MainMenu;
		}
	}
}

void OpenRequestMenu(int reciever, int sender, int betAmount) 
{ 
	if (betAmount != 0)
	{
		Multi1v1_MessageToAll("\x03%N\x01 has challenged \x03%N\x01 over \x03%i\x01 credits!", sender, reciever, betAmount);
	}
	else
	{
		Multi1v1_MessageToAll("\x03%N\x01 has challenged \x03%N\x01!", sender, reciever);
	}
	
	ga_iLastRequest[sender] = GetTime();

	char sInfoBuffer[128], sTitle[128];
	
	Format(sTitle, sizeof(sTitle), "%N Has Challenged You!", sender);
	
	Menu MainMenu = new Menu(RequestMenu_CallBack, MenuAction_Select | MenuAction_End); 
	MainMenu.SetTitle(sTitle); 
	
	MainMenu.AddItem("", "By accepting this challenge,", ITEMDRAW_DISABLED);
	MainMenu.AddItem("", "you will be placed into an", ITEMDRAW_DISABLED);
	MainMenu.AddItem("", "arena to face your challenger.", ITEMDRAW_DISABLED);
	MainMenu.AddItem("", "", ITEMDRAW_DISABLED);
	
	Format(sInfoBuffer, sizeof(sInfoBuffer), "yes;%i;%i", GetClientUserId(sender), betAmount);
	MainMenu.AddItem(sInfoBuffer, "Accept");
	
	Format(sInfoBuffer, sizeof(sInfoBuffer), "no;%i;%i", GetClientUserId(sender), betAmount);
	MainMenu.AddItem(sInfoBuffer, "Decline");
	
	DisplayMenu(MainMenu, reciever, 15); 
}

public int RequestMenu_CallBack(Menu MainMenu, MenuAction action, int param1, int param2) 
{
	switch (action)
	{
		case MenuAction_Select:
		{
			if (!IsValidClient(param1))
			{
				return;
			}

			char sInfo[128], sTempArray[3][128];
			GetMenuItem(MainMenu, param2, sInfo, sizeof(sInfo));
			ExplodeString(sInfo, ";", sTempArray, 3, sizeof(sTempArray[]));
			int sender = GetClientOfUserId(StringToInt(sTempArray[1]));
			int betAmount = StringToInt(sTempArray[2]);
			
			if (StrEqual(sTempArray[0], "yes"))
			{
				if (ga_bIsInChallenge[sender])
				{
					Multi1v1_Message(param1, "They are already in a challenge!");
					return;
				}
				if (isInChallengeQueue(sender))
				{
					Multi1v1_Message(param1, "They are already in a queue for a challenge!");
					return;
				}
				if (ga_iCooldown[sender] > 0)
				{
					Multi1v1_Message(param1, "They must wait %i more rounds to challenge again!", ga_iCooldown[sender]);
					return;
				}
				if (GetClientTeam(sender) == CS_TEAM_SPECTATOR)
				{
					Multi1v1_Message(sender, "They may not challenge as a spectator!");
					return;
				}

				
				if (ga_bIsInChallenge[param1])
				{
					Multi1v1_Message(param1, "You are already in a challenge!");
					return;
				}
				if (isInChallengeQueue(param1))
				{
					Multi1v1_Message(param1, "You are already in a queue for a challenge!");
					return;
				}
				if (ga_iCooldown[param1] > 0)
				{
					Multi1v1_Message(param1, "You must wait %i more rounds to challenge again!", ga_iCooldown[param1]);
					return;
				}
				if (GetClientTeam(param1) == CS_TEAM_SPECTATOR)
				{
					Multi1v1_Message(param1, "You may not challenge as a spectator!");
					return;
				}

				placeInChallengeQueue(param1, sender);
				
				ga_iBetAmount[param1] = betAmount;
				ga_iBetAmount[sender] = betAmount;
				
				Multi1v1_MessageToAll("\x03%N\x01 has accepted \x03%N\x01's challenge!", param1, sender);
				Multi1v1_Message(param1, "\x04You\x01 will be placed into a challenge next round!");
				Multi1v1_Message(sender, "\x04You\x01 will be placed into a challenge next round!");
				
			}
			else
			{
				Multi1v1_Message(sender, "\x03%N \x01has denied \x04your\x01 request!", param1);
			}
		}
		case MenuAction_End: 		
		{
			delete MainMenu;
		}
	}
}


/******************************************************************
************************ MULTI-1V1  *******************************
******************************************************************/


public void Multi1v1_OnRoundWon(int winner, int loser)
{
	if (ga_bIsInChallenge[winner] && ga_bIsInChallenge[loser])
	{
		int betAmount = ga_iBetAmount[winner];
		
		if (betAmount > 0)
		{
			Multi1v1_MessageToAll(" \x03%N\x01 has beaten \x03%N\x01 in a challenge over \x03%i\x01 credits!", winner, loser, betAmount);
		}
		else
		{
			Multi1v1_MessageToAll(" \x03%N\x01 has beaten \x03%N\x01 in a challenge!", winner, loser);
		}
		
		if (g_bZephrusStore && betAmount > 0)
		{
			Store_SetClientCredits(loser, Store_GetClientCredits(loser) - betAmount);
			Store_SetClientCredits(winner, Store_GetClientCredits(winner) + betAmount);
		}
		ga_bIsInChallenge[winner] = false;
		ga_iBetAmount[winner] = 0;
		ga_iCooldown[winner] = gcv_iCooldown.IntValue + 1;
		Multi1v1_UnblockMVPStars(winner);
		Multi1v1_UnblockRatingChanges(winner);

		ga_bIsInChallenge[loser] = false;
		ga_iBetAmount[loser] = 0;
		ga_iCooldown[loser] = gcv_iCooldown.IntValue + 1;
		Multi1v1_UnblockMVPStars(loser);
		Multi1v1_UnblockRatingChanges(loser);

		onChallengeWon(winner, loser);

	}
	else
	{
		ga_iCooldown[winner]--;
		
		ga_iCooldown[loser]--;
	}
}

public void Multi1v1_AfterPlayerSetup(int client)
{
	if (ga_bIsInChallenge[client])
	{
		Multi1v1_Message(client, "\x03You\x01 are now in your challenge!");
		PrintCenterText(client, "<font size=\"24\"><font color='#00ff00'>You</font> are now in your challenge!");
		CS_SetClientClanTag(client, "[CHALLENGE]");
		CS_SetClientContributionScore(client, -1);
		ga_iCooldown[client] = 3;
		
		if (gcv_bBlockRatingChanges.BoolValue)
		{
			Multi1v1_BlockMVPStars(client);
			Multi1v1_BlockRatingChanges(client);
		} 
	}
}

public void Multi1v1_OnPostArenaRankingsSet(ArrayList rankingQueue)
{
        /* Handle Non-Challenge People */
	if (gcv_bSaveOldArena.BoolValue)
	{
		int client;
		for (int i = 0; i < rankingQueue.Length; i++)
		{			
			client = rankingQueue.Get(i);
			if (wasLastRoundAChallenge(client)) // if they had a challenge last round
			{		
				if (ga_iOldArena[client] < rankingQueue.Length - 1) // if we should bother shifting people
				{
					removeFromQueue(rankingQueue, client); // remove them from the ranking queue
					
					rankingQueue.ShiftUp(ga_iOldArena[client]); // shift array up from said index

					rankingQueue.Set(ga_iOldArena[client], client); // set the client back where they were
				}
				
				ga_iOldArena[client] = -1;
			}
		}
	}
	
	/* Handle Challenge People */
	if (challengeQueue.Length > 0)
	{
		int remainder;

		savePlayerArenas(rankingQueue); // save player's arenas who are in challenge queue
		removeAllQueuedPlayers(rankingQueue); // remove all challenge queue players from main queue and save old arena

		if ((rankingQueue.Length % 2) == 0) // if whats left is even
		{
			pushQueuedPlayers(rankingQueue); // push challenger players to rankingQueue
		}
		else // it's odd
		{
			remainder = rankingQueue.Get(rankingQueue.Length - 1); // store the last player
			rankingQueue.Erase(rankingQueue.Length - 1); // remove the last player from ranking queue
			
			pushQueuedPlayers(rankingQueue); // push challenger players
			
			rankingQueue.Push(remainder); // tag remainder onto the end
		}

#if defined DEBUG
		outputArrayContents(rankingQueue, "---- RANKING QUEUE ----");
		outputArrayContents(challengeQueue, "---- CHALLENGE QUEUE ----");
#endif
		
		onRankingQueueBuilt(rankingQueue);
		
		challengeQueue.Clear(); // clear array for next round :D
	}
}

// DESCRIPTION: Determines if the last round for a client was a challenge
bool wasLastRoundAChallenge(int client)
{
	if (ga_iOldArena[client] != -1)
	{
		return true;
	}
	else
	{
		return false;
	}
}

// DESCRIPTION: Places two clients into the challengeQueue 
void placeInChallengeQueue(int client1, int client2)
{
	if (IsValidClient(client1) && IsValidClient(client2))
	{
		challengeQueue.Push(client1);
		challengeQueue.Push(client2);
	}
}

void savePlayerArenas(ArrayList array)
{
	for (int i = 0; i < array.Length; i++)
	{
		int client = array.Get(i);
		if (challengeQueue.FindValue(client) != -1)
		{
			ga_iOldArena[client] = i;
		}
	}
}

// DESCRPTION: Removes ALL challengeQueue players from specified queue.
void removeAllQueuedPlayers(ArrayList array)
{
	int index, client;
	for (int i = 0; i < challengeQueue.Length; i++)
	{
		client = challengeQueue.Get(i);
		index = array.FindValue(client);
		
		while (index != -1)
		{
			array.Erase(index);
			
			index = array.FindValue(client);
		}
	}

}

// DESCRPTION: Pushes all players in challengeQueue to the destination
void pushQueuedPlayers(ArrayList destination)
{
	int client;
	for (int i = 0; i < challengeQueue.Length; i++)
	{
		client = challengeQueue.Get(i);

		destination.Push(client);
		ga_bIsInChallenge[client] = true;
	} 
}

// DESCRPTION: Removes a client from specified queue
void removeFromQueue(ArrayList queue, int client)
{
	int index = queue.FindValue(client);
	while (index != -1)
	{
		queue.Erase(index);
		
		index = queue.FindValue(client);
	}
}

// DESCRPTION: Checks if a client is in the challengeQueue
bool isInChallengeQueue(int client)
{
	int returnValue = challengeQueue.FindValue(client);
	
	if (returnValue == -1)
	{
		return false;
	}
	else
	{
		return true;
	}
}

// DESCRIPTION: Debug method to help visualize array
stock void outputArrayContents(ArrayList array, const char[] phrase)
{
	PrintToChatAll(phrase);

	for (int i = 0; i < array.Length; i++)
	{
		PrintToChatAll("Array Index %i: %N", i, array.Get(i));
	}
}

// DESCRIPTION: Removes a player and their partner from challenge queue
int removePairFromQueue(int client)
{
	int arena = Multi1v1_GetArenaNumber(client);
	
	int player1 = Multi1v1_GetArenaPlayer1(arena);
	int player2 = Multi1v1_GetArenaPlayer2(arena);
	
	removeFromQueue(challengeQueue, player1);
	removeFromQueue(challengeQueue, player2);
	
	if (player1 == client)
	{
		return player2;
	}
	else
	{
		return player1;
	}
}

// DESCRIPTION: Gets the index of one's partner
int getClientParter(int client)
{
	int arena = Multi1v1_GetArenaNumber(client);

	int player1 = Multi1v1_GetArenaPlayer1(arena);
	int player2 = Multi1v1_GetArenaPlayer2(arena);
	
	if (player1 == client)
	{
		return player2;
	}
	else
	{
		return player1;
	}
}

bool IsValidClient(int client, bool bAllowBots = false, bool bAllowDead = true)
{
	if(!(1 <= client <= MaxClients) || !IsClientInGame(client) || (IsFakeClient(client) && !bAllowBots) || IsClientSourceTV(client) || IsClientReplay(client) || (!bAllowDead && !IsPlayerAlive(client)))
	{
		return false;
	}
	return true;
}

bool isValidBetAmount(int player1, int player2, int betAmount)
{

	if (Store_GetClientCredits(player1) < betAmount)
	{
		return false;
	}
	else if (Store_GetClientCredits(player2) < betAmount)
	{
		return false;
	}
	else
	{
		return true;
	}
}

void SaveCookies(int client)
{
	if(gcv_bPluginEnabled.BoolValue && IsValidClient(client))
	{
		char playerPreference[8];
		IntToString(view_as<int>(!ga_bChallengePref[client]), playerPreference, sizeof(playerPreference));
		SetClientCookie(client, g_hClientCookie, playerPreference);
	}
}
void LoadCookies(int client)
{
	if(gcv_bPluginEnabled.BoolValue && IsValidClient(client))
	{
		char playerPreference[8];
		GetClientCookie(client, g_hClientCookie, playerPreference, sizeof(playerPreference));
		ga_bChallengePref[client] = !view_as<bool>(StringToInt(playerPreference));
	}
}
