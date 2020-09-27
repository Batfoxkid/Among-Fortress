#pragma semicolon 1

#include <sourcemod>
#include <tf2_stocks>
#include <sdkhooks>
#include <sdktools>
#include <tf2items>
#include <morecolors>
#include <tf2attributes>
#include <dhooks>
#include <sendproxy>
#undef REQUIRE_PLUGIN
#tryinclude <sourcecomms>
#tryinclude <basecomm>
#define REQUIRE_PLUGIN

#pragma newdecls required

#define DEBUG

#define MAJOR_REVISION	"0"
#define MINOR_REVISION	"2"
#define STABLE_REVISION	"0"
#define PLUGIN_VERSION	MAJOR_REVISION..."."...MINOR_REVISION..."."...STABLE_REVISION

#define FAR_FUTURE	100000000.0
#define MAXTF2PLAYERS	36
#define MAXANGLEPITCH	45.0
#define MAXANGLEYAW	90.0
#define MAXTIME		898

#define PREFIX		"{darkred}[Among]{default} "

static const float OFF_THE_MAP[3] = { 16383.0, 16383.0, -16383.0 };
static const float TRIPLE_D[3] = { 0.0, 0.0, 0.0 };

static const char ClassNames[][] =
{
	"Mercenary",
	"Scout",
	"Sniper",
	"Soldier",
	"Demoman",
	"Medic",
	"Heavy",
	"Pyro",
	"Spy",
	"Engineer"
};

static const char ClientColor[][] =
{
	"snow",
	"red",
	"yellow",
	"green",
	"blue",
	"gray",
	"black",
	"collectors",
	"community",
	"genuine",
	"haunted",	// 10
	"normal",
	"selfmade",
	"strange",
	"unique",
	"unusual",
	"valve",
	"vintage",
	"brown",
	"allies",
	"axis",		// 20
	"pink",
	"ancient",
	"arcana",
	"common",
	"corrupted",
	"exalted",
	"frozen",
	"immortal",
	"legendary",	// 30
	"mythical",
	"rare",
	"uncommon",
	"tomato",
	"deeppink",
	"coral"
};

public Plugin myinfo =
{
	name		=	"Secret Fortress Engine",
	author		=	"Batfoxkid",
	description	=	"WHY DID YOU THROW A GRENADE INTO THE ELEVA-",
	version		=	PLUGIN_VERSION
};

enum RoundEnum
{
	Round_None = 0,
	Round_Waiting,
	Round_Active,
	Round_CrewWin,
	Round_FakeWin
}

enum StatusEnum
{
	Status_Spec = 0,
	Status_Dead,
	Status_Alive
}

enum VoteEnum
{
	Vote_None = 0,
	Vote_Wait,
	Vote_On
}

enum EntityEnum
{
	Ent_Unknown = -1,

	Info_Name = 0,
	Relay_Done,
	Relay_Check,
	Relay_Major,
	Info_Count,
	Relay_Menu,

	Prop_Trigger = 10,
	Button_Trigger,
	Info_Vent,
	Relay_Vent,
	Relay_Meeting,
	Relay_RoundEnd,
	Info_Kicked
};

static const char FireDeath[][] =
{
	"primary_death_burning",
	"PRIMARY_death_burning"
};

static const float FireDeathTimes[] =
{
	4.2,	// Merc
	3.2,	// Scout
	4.7,	// Sniper 	
	4.2,	// Soldier
	2.5,	// Demoman
	3.6,	// Medic 
	3.5,	// Heavy	
	0.0,	// Pyro
	2.2,	// Spy
	3.8	// Engineer
};

enum struct TaskEnum
{
	char Name[64];

	int Count;
	int Major;

	int Left[MAXTF2PLAYERS];
}

enum struct ClientEnum
{
	StatusEnum Status;
	bool Imposter;
	int Team;

	bool CanTalkTo[MAXTF2PLAYERS];

	int Points;
	int Streak;
	int StoredPoints;
	int Vote;

	float KillIn;
	float ViewRange;
}

bool Enabled = false;
bool SourceComms;	// SourceComms++
bool BaseComm;	// BaseComm

Handle TimerTraining;
bool TrainingOn;

RoundEnum RoundMode;

VoteEnum VoteMode;
Menu MenuVote;
Handle TimerVote;

int TasksDone;
TaskEnum Tasks[32];
#define MAXTASKS (sizeof(Tasks)-1)

float EventIn;
float EventTime;

int Crewmates;
int Imposters;

ConVar CvarTournament;
ConVar CvarTeamNameRed;
ConVar CvarTeamNameBlu;

Handle SDKTeamAddPlayer;
Handle SDKTeamRemovePlayer;
Handle DHRoundRespawn;
Handle DHIsInTraining;
Handle DHGameType;

ClientEnum Client[MAXTF2PLAYERS];

// SourceMod Events

public void OnPluginStart()
{
	HookEvent("teamplay_round_start", OnRoundStart, EventHookMode_PostNoCopy);
	HookEvent("teamplay_round_win", OnRoundEnd, EventHookMode_PostNoCopy);
	HookEvent("teamplay_broadcast_audio", OnBroadcast, EventHookMode_Pre);
	HookEvent("player_death", OnPlayerDeath, EventHookMode_Pre);
	HookEvent("player_death", OnPlayerDeathPost, EventHookMode_PostNoCopy);
	HookEvent("player_spawn", OnPlayerSpawn);
	HookEvent("teamplay_win_panel", OnWinPanel, EventHookMode_Pre);

	CvarTournament = FindConVar("mp_tournament");
	CvarTeamNameRed = FindConVar("mp_tournament_redteamname");
	CvarTeamNameBlu = FindConVar("mp_tournament_blueteamname");

	AddCommandListener(OnSayCommand, "say");
	AddCommandListener(OnSayCommand, "say_team");
	//AddCommandListener(OnSewerSlide, "explode");
	//AddCommandListener(OnSewerSlide, "kill");
	AddCommandListener(OnJoinClass, "joinclass");
	AddCommandListener(OnJoinClass, "join_class");
	AddCommandListener(OnJoinSpec, "spectate");
	AddCommandListener(OnJoinTeam, "jointeam");
	AddCommandListener(OnJoinAuto, "autoteam");
	AddCommandListener(OnVoiceMenu, "voicemenu");

	#if defined _sourcecomms_included
	SourceComms = LibraryExists("sourcecomms++");
	#endif

	#if defined _basecomm_included
	BaseComm = LibraryExists("basecomm");
	#endif

	Tasks[MAXTASKS].Count = 1;
	Tasks[MAXTASKS].Major = -1;

	AddNormalSoundHook(HookSound);

	HookEntityOutput("logic_relay", "OnTrigger", OnRelayTrigger);
	AddTempEntHook("Player Decal", OnPlayerSpray);

	LoadTranslations("core.phrases");
	LoadTranslations("common.phrases");
	LoadTranslations("among-fortress.phrases");

	GameData gamedata = new GameData("among-fortress");
	if(gamedata)
	{
		StartPrepSDKCall(SDKCall_Entity);
		PrepSDKCall_SetFromConf(gamedata, SDKConf_Virtual, "CTeam::AddPlayer");
		PrepSDKCall_AddParameter(SDKType_CBasePlayer, SDKPass_Pointer);
		SDKTeamAddPlayer = EndPrepSDKCall();
		if(!SDKTeamAddPlayer)
			LogError("[Gamedata] Could not find CTeam::AddPlayer");

		StartPrepSDKCall(SDKCall_Entity);
		PrepSDKCall_SetFromConf(gamedata, SDKConf_Virtual, "CTeam::RemovePlayer");
		PrepSDKCall_AddParameter(SDKType_CBasePlayer, SDKPass_Pointer);
		SDKTeamRemovePlayer = EndPrepSDKCall();
		if(!SDKTeamRemovePlayer)
			LogError("[Gamedata] Could not find CTeam::RemovePlayer");

		Handle detour = DHookCreateFromConf(gamedata, "CTFPlayer::SaveMe");
		if(detour)
		{
			DHookEnableDetour(detour, false, DHook_Supercede);
			delete detour;
		}
		else
		{
			LogError("[Gamedata] Could not find CTFPlayer::SaveMe");
		}

		detour = DHookCreateFromConf(gamedata, "CTFPlayer::DropAmmoPack");
		if(detour)
		{
			DHookEnableDetour(detour, false, DHook_Supercede);
			delete detour;
		}
		else
		{
			LogError("[Gamedata] Could not find CTFPlayer::DropAmmoPack");
		}

		DHRoundRespawn = DHookCreateFromConf(gamedata, "CTeamplayRoundBasedRules::RoundRespawn");
		if(!DHRoundRespawn)
			SetFailState("[Gamedata] Could not find CTFPlayer::RoundRespawn");

		DHIsInTraining = DHookCreate(gamedata.GetOffset("CTFGameRules::IsInTraining"), HookType_GameRules, ReturnType_Bool, ThisPointer_Address);
		if(!DHIsInTraining)
			LogError("[Gamedata] Could not find CTFGameRules::IsInTraining");

		DHGameType = DHookCreate(gamedata.GetOffset("CTFGameRules::GetGameType"), HookType_GameRules, ReturnType_Int, ThisPointer_Address);
		if(!DHGameType)
			LogError("[Gamedata] Could not find CTFGameRules::GetGameType");

		delete gamedata;
	}
	else
	{
		SetFailState("[Gamedata] Could not find among-fortress.txt");
	}

	for(int i=1; i<=MaxClients; i++)
	{
		if(IsValidClient(i))
			OnClientPutInServer(i);
	}
}

public void OnMapStart()
{
	PrecacheModel("models/props_halloween/ghost_no_hat.mdl", true);
}

public void OnLibraryAdded(const char[] name)
{
	#if defined _basecomm_included
	if(StrEqual(name, "basecomm"))
	{
		BaseComm = true;
		return;
	}
	#endif

	#if defined _sourcecomms_included
	if(StrEqual(name, "sourcecomms++"))
		SourceComms = true;
	#endif
}

public void OnLibraryRemoved(const char[] name)
{
	#if defined _basecomm_included
	if(StrEqual(name, "basecomm"))
	{
		BaseComm = false;
		return;
	}
	#endif

	#if defined _sourcecomms_included
	if(StrEqual(name, "sourcecomms++"))
		SourceComms = false;
	#endif
}

// Game Events

public void OnConfigsExecuted()
{
	RoundMode = Round_None;
	TrainingOn = false;
	TimerTraining = INVALID_HANDLE;

	if(MenuVote != INVALID_HANDLE)
		delete MenuVote;

	MenuVote = new Menu(Handler_Vote);

	#if defined DEBUG
	Enabled = true;
	#else
	char buffer[PLATFORM_MAX_PATH];
	GetCurrentMap(buffer, sizeof(buffer));
	Enabled = !StrContains(buffer, "au_", false);
	#endif

	if(Enabled)
		SetCommandFlags("firstperson", GetCommandFlags("firstperson") & ~FCVAR_CHEAT);

	int entity = FindEntityByClassname(-1, "tf_player_manager");
	if(entity > MaxClients)
	{
		for(int i=1; i<=MaxClients; i++)
		{
			SendProxy_HookArrayProp(entity, "m_bAlive", i, Prop_Int, SendProp_OnAlive);
			SendProxy_HookArrayProp(entity, "m_iTeam", i, Prop_Int, SendProp_OnTeam);
			SendProxy_HookArrayProp(entity, "m_iScore", i, Prop_Int, SendProp_OnScore);
		}
	}

	if(DHRoundRespawn)
		DHookGamerules(DHRoundRespawn, false, _, DHook_RoundRespawn);

	if(DHIsInTraining)
		DHookGamerules(DHIsInTraining, false, _, DHook_IsInTraining);

	if(DHGameType)
		DHookGamerules(DHGameType, true, _, DHook_GetGameType);
}

public void OnClientPutInServer(int client)
{
	if(!Enabled)
		return;

	if(RoundMode == Round_Waiting)
		CreateTimer(3.0, CheckWaitingPlayers, _, TIMER_FLAG_NO_MAPCHANGE);

	Client[client] = Client[0];
	if(CvarTournament)
		CvarTournament.ReplicateToClient(client, "1");

	SDKHook(client, SDKHook_SetTransmit, OnTransmit);
}

public void OnMapEnd()
{
	if(Enabled)
	{
		if(CvarTeamNameRed)
			CvarTeamNameRed.RestoreDefault();

		if(CvarTeamNameBlu)
			CvarTeamNameBlu.RestoreDefault();
	}
}

public void OnRoundEnd(Event event, const char[] name, bool dontBroadcast)
{
	if(!Enabled || RoundMode<Round_Active)
		return;

	if(RoundMode!=Round_CrewWin && RoundMode!=Round_FakeWin)
		RoundMode = Round_FakeWin;

	if(CvarTeamNameRed)
		CvarTeamNameRed.SetString("CREWMATES");

	if(CvarTeamNameBlu)
		CvarTeamNameBlu.SetString("IMPOSTERS");

	UpdateListenOverrides();
	PrintTrainingStart(14.75);

	int total, fakes, reals;
	bool imposter = RoundMode==Round_FakeWin;
	int[] clients = new int[MaxClients];
	for(int client=1; client<=MaxClients; client++)
	{
		if(!IsValidClient(client))
			continue;

		clients[total++] = client;
		if(Client[client].Status == Status_Spec)
		{
			Client[client].Team = 1;
			PrintTraining(client, true, "%T", imposter ? "win_fake" : "win_crew", client);
		}
		else if(Client[client].Imposter)
		{
			Client[client].Team = 3;
			Client[client].Streak = imposter ? Client[client].Streak+1 : 0;
			PrintTraining(client, true, "%T", imposter ? "win" : "lose", client);
			if(Client[client].Status == Status_Alive)
			{
				fakes++;
				ChangeClientTeamEx(client, 3);
				if(imposter)
					TF2_RegeneratePlayer(client);
			}
		}
		else
		{
			Client[client].Team = 2;
			Client[client].Streak = imposter ? 0 : Client[client].Streak+1;
			PrintTraining(client, true, "%T", imposter ? "lose" : "win", client);
			if(Client[client].Status == Status_Alive)
			{
				reals++;
				if(!imposter)
					TF2_RegeneratePlayer(client);
			}
		}
	}

	for(int i; i<total; i++)
	{
		PrintTraining(clients[i], false, "%T", "round_end", clients[i], reals, Crewmates, fakes, Imposters);
	}
}

public void OnRoundStart(Event event, const char[] name, bool dontBroadcast)
{
	if(Enabled)
	{
		UpdateListenOverrides();

		if(RoundMode == Round_Waiting)
		{
			CreateTimer(5.0, CheckWaitingPlayers, _, TIMER_FLAG_NO_MAPCHANGE);
		}
		else
		{
			if(CvarTeamNameRed)
				CvarTeamNameRed.SetString("ALIVE");

			if(CvarTeamNameBlu)
				CvarTeamNameBlu.SetString("DEAD");

			int entity = -1;
			while((entity=FindEntityByClassname2(entity, "func_respawnroomvisualizer")) != -1)
			{
				AcceptEntityInput(entity, "Disable");
			}

			for(entity=0; entity<MAXTASKS; entity++)
			{
				Tasks[entity] = Tasks[MAXTASKS];
			}

			entity = -1;
			while((entity=FindEntityByClassname2(entity, "info_target")) != -1)
			{
				int id = -1;
				int info;
				if(GetRelayType(entity, id, info)==Relay_Check && id>=0 && id<MAXTASKS)
					Tasks[id].Major = info;
			}

			int highest = -1;
			entity = -1;
			while((entity=FindEntityByClassname2(entity, "logic_relay")) != -1)
			{
				static char buffer[64];
				GetEntPropString(entity, Prop_Data, "m_iName", buffer, sizeof(buffer));
				int id = -1;
				int info;
				EntityEnum type = GetInfoType(buffer, sizeof(buffer), id, info);
				if(id<0 || id>=MAXTASKS)
					continue;

				highest = id;
				switch(type)
				{
					case Info_Count:
						Tasks[id].Count = info;

					case Info_Name:
						strcopy(Tasks[id].Name, sizeof(Tasks[].Name), buffer);
				}
			}

			if(highest == -1)
			{
				#if !defined DEBUG
				char buffer[96];
				GetCurrentMap(buffer, sizeof(buffer));
				SetFailState("No tasks were found on %s", buffer);
				#endif
				return;
			}

			int amount = highest;
			if(amount > 5)
				amount = 5;

			int[] pool = new int[highest];
			for(int i; i<highest; i++)
			{
				pool[i] = i;
			}

			for(int client=1; client<=MaxClients; client++)
			{
				if(!IsClientInGame(client) || Client[client].Status!=Status_Alive || Client[client].Imposter)
					continue;

				SortIntegers(pool, highest, Sort_Random);
				for(int i; i<amount; i++)
				{
					Tasks[pool[i]].Left[client] = Tasks[pool[i]].Count;
				}
			}
		}
	}
}

public Action OnWinPanel(Event event, const char[] name, bool dontBroadcast)
{
	return Plugin_Handled;
}

public Action OnRelayTrigger(const char[] output, int entity, int client, float delay)
{
	int id = -1;
	int info;
	EntityEnum type = GetRelayType(entity, id, info);
	switch(type)
	{
		/*case Ent_Unknown:
		{
		}
		case Relay_RoundEnd:
		{
		}*/
		case Relay_Meeting:
		{
			if(IsValidClient(client))
				StartMeeting(client, true);
		}
		case Relay_Vent:
		{
		}
		default:
		{
			if(id>=0 && id<MAXTASKS)
			{
				switch(type)
				{
					case Relay_Check:
					{
						if(IsValidClient(client) && !Client[client].Imposter && Tasks[id].Left[client]>0)
						{
							AcceptEntityInput(entity, "FireUser1", client, client);
						}
						else
						{
							AcceptEntityInput(entity, "FireUser2", client, client);
						}
					}
					case Relay_Done:
					{
						if(Tasks[id].Major >= 0)
						{
							
						}
						else if(IsValidClient(client) && Tasks[id].Left[client]>0)
						{
							AcceptEntityInput(entity, "FireUser1", client, client);
						}
					}
					case Relay_Major:
					{
					}
					/*case Relay_Menu:
					{
					}*/
				}
			}
		}
	}
	return Plugin_Continue;
}

public void OnPlayerSpawn(Event event, const char[] name, bool dontBroadcast)
{
	if(Enabled)
	{
		int client = GetClientOfUserId(event.GetInt("userid"));
		if(client && IsClientInGame(client))
		{
			SetEntProp(client, Prop_Send, "m_nStreaks", Client[client].Streak);
			if(RoundMode == Round_Active)
			{
				if(Client[client].Status == Status_Alive)
				{
					GiveFists(client);
				}
				else
				{
					TurnIntoGhost(client);
				}
			}
		}
	}
}

/*public Action OnSewerSlide(int client, const char[] command, int args)
{
	if(Enabled && client && RoundMode==Round_Active)
	{
		return Plugin_Handled;
	}
	return Plugin_Continue;
}*/

public Action OnJoinClass(int client, const char[] command, int args)
{
	if(Enabled && client && RoundMode==Round_Active && (Client[client].Status!=Status_Alive || view_as<TFClassType>(GetEntProp(client, Prop_Send, "m_iDesiredPlayerClass"))==TFClass_Unknown))
		return Plugin_Handled;

	return Plugin_Continue;
}

public Action OnPlayerSpray(const char[] name, const int[] clients, int count, float delay)
{
	if(Enabled)
	{
		int client = TE_ReadNum("m_nPlayer");
		if(IsClientInGame(client) && Client[client].Status!=Status_Alive)
			return Plugin_Handled;
	}
	return Plugin_Continue;
}

public Action OnJoinAuto(int client, const char[] command, int args)
{
	if(Enabled && client)
	{
		if(GetClientTeam(client) <= view_as<int>(TFTeam_Spectator))
		{
			ChangeClientTeam(client, view_as<int>(TFTeam_Red));
			ShowVGUIPanel(client, "class_red");
			if(RoundMode == Round_Waiting)
				CreateTimer(5.0, CheckWaitingPlayers, _, TIMER_FLAG_NO_MAPCHANGE);
		}
		return Plugin_Handled;
	}
	return Plugin_Continue;
}

public Action OnJoinSpec(int client, const char[] command, int args)
{
	if(Enabled && client)
	{
		Client[client].Status = Status_Spec;
		CreateTimer(0.4, CheckAlivePlayers, _, TIMER_FLAG_NO_MAPCHANGE);
	}
	return Plugin_Continue;
}

public Action OnJoinTeam(int client, const char[] command, int args)
{
	if(Enabled && client)
	{
		static char teamString[10];
		GetCmdArg(1, teamString, sizeof(teamString));
		if(StrEqual(teamString, "spectate", false))
		{
			Client[client].Status = Status_Spec;
		}
		else
		{
			if(GetClientTeam(client) <= view_as<int>(TFTeam_Spectator))
			{
				ChangeClientTeam(client, view_as<int>(TFTeam_Red));
				ShowVGUIPanel(client, "class_red");
				if(RoundMode == Round_Waiting)
					CreateTimer(5.0, CheckWaitingPlayers, _, TIMER_FLAG_NO_MAPCHANGE);
			}
			return Plugin_Handled;
		}
	}
	return Plugin_Continue;
}

public Action OnVoiceMenu(int client, const char[] command, int args)
{
	if(Enabled && client && RoundMode<=Round_Active && IsPlayerAlive(client))
	{
		if(Client[client].Status!=Status_Alive && GetClientTeam(client)>view_as<int>(TFTeam_Spectator))
		{
			TF2_RespawnPlayer(client);
		}
		else if(AttemptGrabItem(client))
		{
			
		}

		if(VoteMode == Vote_None)
			return Plugin_Handled;
	}
	return Plugin_Continue;
}

public Action OnSayCommand(int client, const char[] command, int args)
{
	if(!client || !Enabled)
		return Plugin_Continue;

	#if defined _sourcecomms_included
	if(SourceComms && SourceComms_GetClientGagType(client)>bNot)
		return Plugin_Handled;
	#endif

	#if defined _basecomm_included
	if(BaseComm && BaseComm_IsClientGagged(client))
		return Plugin_Handled;
	#endif

	float time = GetEngineTime();
	static float delay[MAXTF2PLAYERS];
	if(delay[client] > time)
		return Plugin_Handled;

	delay[client] = time+1.5;

	static char msg[256];
	GetCmdArgString(msg, sizeof(msg));
	if(msg[1]=='/' || msg[1]=='@')
		return Plugin_Handled;

	//CRemoveTags(msg, sizeof(msg));
	ReplaceString(msg, sizeof(msg), "\"", "");
	ReplaceString(msg, sizeof(msg), "\n", "");

	if(!strlen(msg))
		return Plugin_Handled;

	char name[128];
	GetClientName(client, name, sizeof(name));
	CRemoveTags(name, sizeof(name));
	Format(name, sizeof(name), "{%s}%s", ClientColor[client], name);

	Handle iter = GetPluginIterator();
	while(MorePlugins(iter))
	{
		Handle plugin = ReadPlugin(iter);
		Function func = GetFunctionByName(plugin, "SCPSF_OnChatMessage");
		if(func == INVALID_FUNCTION)
			continue;

		Call_StartFunction(plugin, func);
		Call_PushCell(client);
		Call_PushStringEx(name, sizeof(name), SM_PARAM_STRING_UTF8|SM_PARAM_STRING_COPY, SM_PARAM_COPYBACK);
		Call_PushStringEx(msg, sizeof(msg), SM_PARAM_STRING_UTF8|SM_PARAM_STRING_COPY, SM_PARAM_COPYBACK);
		Call_Finish();
	}
	delete iter;

	if(RoundMode != Round_Active)
	{
		for(int target=1; target<=MaxClients; target++)
		{
			if(target==client || (IsValidClient(target, false) && Client[client].CanTalkTo[target]))
				CPrintToChat(target, "%s {default}: %s", name, msg);
		}
		return Plugin_Handled;
	}

	switch(Client[client].Status)
	{
		case Status_Alive:
		{
			for(int target=1; target<=MaxClients; target++)
			{
				if(target==client || (IsValidClient(target, false) && Client[client].CanTalkTo[target]))
					CPrintToChat(target, "%s {default}: %s", name, msg);
			}
		}
		case Status_Dead:
		{
			for(int target=1; target<=MaxClients; target++)
			{
				if(target==client || (IsValidClient(target, false) && Client[client].CanTalkTo[target] && Client[client].Status!=Status_Alive))
					CPrintToChat(target, "*DEAD* %s {default}: %s", name, msg);
			}
		}
		default:
		{
			if(CheckCommandAccess(client, "sm_mute", ADMFLAG_CHAT) && GetClientTeam(client)<=view_as<int>(TFTeam_Spectator))
			{
				CPrintToChatAll("*SPEC* %s {default}: %s", name, msg);
			}
			else
			{
				for(int target=1; target<=MaxClients; target++)
				{
					if(target==client || (IsValidClient(target, false) && Client[client].CanTalkTo[target] && Client[client].Status!=Status_Alive))
						CPrintToChat(target, "*SPEC* %s {default}: %s", name, msg);
				}
			}
		}
	}
	return Plugin_Handled;
}

public void OnClientDisconnect(int client)
{
	if(Enabled && RoundMode==Round_Active)
		CreateTimer(0.3, CheckAlivePlayers, _, TIMER_FLAG_NO_MAPCHANGE);
}

public Action TF2Items_OnGiveNamedItem(int client, char[] classname, int index, Handle &item)
{
	if(Enabled && RoundMode==Round_Active)
	{
		if(index==405 || index==608 || index==1101 || !StrContains(classname, "tf_weapon", false) || StrEqual(classname, "tf_wearable_demoshield", false))
			return Plugin_Stop;
	}
	return Plugin_Continue;
}

public Action OnPlayerDeath(Event event, const char[] name, bool dontBroadcast)
{
	if(Enabled)
	{
		int userid = event.GetInt("userid");
		int client = GetClientOfUserId(userid);
		if(client)
		{
			RequestFrame(RemoveRagdoll, userid);
			if(Client[client].Status != Status_Alive)
				return Plugin_Handled;

			Client[client].Status = Status_Dead;
		}
	}
	return Plugin_Continue;
}

public void OnPlayerDeathPost(Event event, const char[] name, bool dontBroadcast)
{
	KillEvent();
}

void KillEvent()
{
	CreateTimer(0.4, CheckAlivePlayers, _, TIMER_FLAG_NO_MAPCHANGE);
	UpdateListenOverrides();
}

public Action OnBroadcast(Event event, const char[] name, bool dontBroadcast)
{
	static char sound[PLATFORM_MAX_PATH];
	event.GetString("sound", sound, sizeof(sound));
	if(!StrContains(sound, "Game.Your", false) || StrEqual(sound, "Game.Stalemate", false) || !StrContains(sound, "Announcer.", false))
		return Plugin_Handled;

	return Plugin_Continue;
}

public Action OnPlayerRunCmd(int client, int &buttons)
{
	if(!Enabled || !IsPlayerAlive(client))
		return Plugin_Continue;

	bool changed;
	float engineTime = GetEngineTime();
	static int holding[MAXTF2PLAYERS];
	if(VoteMode == Vote_None)
	{
		if(holding[client])
		{
			if(!(buttons & holding[client]))
				holding[client] = 0;
		}
		else if(buttons & IN_ATTACK)
		{
			if(RoundMode==Round_Active && Client[client].Status==Status_Alive && Client[client].Imposter && Client[client].KillIn<engineTime)
			{
				int target = GetClientPointVisible(client, 350.0);
				if(IsValidClient(target) && Client[target].Status==Status_Alive && !Client[target].Imposter)
				{
					static float pos[3];
					GetEntPropVector(target, Prop_Send, "m_vecOrigin", pos);
					TeleportEntity(client, pos, NULL_VECTOR, NULL_VECTOR);

					Client[target].Status = Status_Dead;
					TurnIntoGhost(target);
					Client[client].KillIn = engineTime+45.0;
					CreateSpecialDeath(target);
					KillEvent();

					int clients[2];
					clients[0] = client;
					clients[1] = target;
					ShowDeathNotice(clients, sizeof(clients), GetClientUserId(client), GetClientUserId(target), 0, -1, "backstab", DMG_CRIT, 0);
				}

				buttons &= ~IN_ATTACK;
				changed = true;
			}
			else if((RoundMode==Round_Active || Client[client].Status==Status_Alive) && AttemptGrabItem(client))
			{
				buttons &= ~IN_ATTACK;
				changed = true;
				holding[client] = IN_ATTACK;
			}
			else
			{
				holding[client] = IN_ATTACK;
			}
		}
		else if(buttons & IN_ATTACK2)
		{
			if(RoundMode==Round_Active || Client[client].Status==Status_Alive)
			{
				if(CheckForBodies(client))
				{
					StartMeeting(client, false);
					buttons &= ~IN_ATTACK2;
					changed = true;
				}
				else if(AttemptGrabItem(client))
				{
					buttons &= ~IN_ATTACK2;
					changed = true;
				}
			}
			holding[client] = IN_ATTACK2;
		}
		else if(buttons & IN_RELOAD)
		{
			if((RoundMode==Round_Active || Client[client].Status==Status_Alive) && AttemptGrabItem(client))
			{
				buttons &= ~IN_RELOAD;
				changed = true;
			}
			holding[client] = IN_RELOAD;
		}
		else if(buttons & IN_ATTACK3)
		{
			if((RoundMode==Round_Active || Client[client].Status==Status_Alive) && AttemptGrabItem(client))
			{
				buttons &= ~IN_ATTACK3;
				changed = true;
			}
			holding[client] = IN_ATTACK3;
		}
		else if(buttons & IN_USE)
		{
			if((RoundMode==Round_Active || Client[client].Status==Status_Alive) && AttemptGrabItem(client))
			{
				buttons &= ~IN_USE;
				changed = true;
			}
			holding[client] = IN_USE;
		}
	}

	if(RoundMode == Round_Active)
	{
		static float specialTick[MAXTF2PLAYERS];
		if(specialTick[client] < engineTime)
		{
			specialTick[client] = engineTime+0.5;
			ClientCommand(client, "firstperson");
			SetGlobalTransTarget(client);
			if(VoteMode==Vote_None && Client[client].Status==Status_Alive)
			{
				if(Client[client].Imposter)
				{
					if(Client[client].KillIn > engineTime)
					{
						SetHudTextParams(-1.0, 0.84, 0.7, 155, 155, 155, 255);
						ShowHudText(client, 1, "%t", "kill_not", RoundToCeil(Client[client].KillIn-engineTime));
					}
					else
					{
						SetHudTextParams(-1.0, 0.84, 0.7, 255, 255, 255, 255);
						ShowHudText(client, 1, "%t", "kill_ready");
					}

					if(EventIn > engineTime)
					{
						SetHudTextParams(-1.0, 0.92, 0.7, 155, 155, 155, 255);
						ShowHudText(client, 2, "%t", "event_not", RoundToCeil(EventIn-engineTime));
					}
					else
					{
						SetHudTextParams(-1.0, 0.92, 0.7, 255, 255, 255, 255);
						ShowHudText(client, 2, "%t", "event_ready");
					}
				}

				bool found;
				if(holding[client] != IN_ATTACK2)
					found = CheckForBodies(client);

				if(found)
				{
					SetHudTextParams(-1.0, 0.88, 0.7, 255, 255, 255, 255);
					ShowHudText(client, 0, "%t", "body_ready");
				}
				else
				{
					SetHudTextParams(-1.0, 0.88, 0.7, 155, 155, 155, 255);
					ShowHudText(client, 0, "%t", "body_not");
				}
			}

			static char buffer[256];
			if(Client[client].Imposter)
			{
				if(VoteMode == Vote_None)
					Format(buffer, sizeof(buffer), "%t\n ", "tasks_total", TasksDone);

				Format(buffer, sizeof(buffer), "%s\n%t", buffer, "your_allies");
				for(int i=1; i<=MaxClients; i++)
				{
					if(i!=client && IsClientInGame(i) && Client[i].Imposter && Client[i].Status==Status_Alive)
						Format(buffer, sizeof(buffer), "%s\n%N", buffer, i);
				}
			}
			else if(VoteMode == Vote_None)
			{
				Format(buffer, sizeof(buffer), "%t\n ", "tasks_total", TasksDone);
				for(int i; i<MAXTASKS; i++)
				{
					if(Tasks[i].Left[client] > 0)
						Format(buffer, sizeof(buffer), "%s\n%s (%d/%d)", buffer, Tasks[i].Name, (Tasks[i].Count-Tasks[i].Left[client]), Tasks[i].Count);
				}
			}

			PrintKeyHintText(client, buffer);
		}
	}
	return changed ? Plugin_Changed : Plugin_Continue;
}

// Hook Events

public Action HookSound(int clients[MAXPLAYERS], int &numClients, char sample[PLATFORM_MAX_PATH], int &entity, int &channel, float &volume, int &level, int &pitch, int &flags, char soundEntry[PLATFORM_MAX_PATH], int &seed)
{
	if(!Enabled || !IsValidClient(entity))
		return Plugin_Continue;

	if(!StrContains(sample, "vo", false) && Client[entity].Status!=Status_Alive)
		return Plugin_Handled;

	return Plugin_Continue;
}

public Action OnTransmit(int client, int target)
{
	if(!Enabled || client==target || !IsValidClient(target) || IsClientObserver(target) || TF2_IsPlayerInCondition(target, TFCond_HalloweenGhostMode))
		return Plugin_Continue;

	if(TF2_IsPlayerInCondition(client, TFCond_HalloweenGhostMode))
		return Plugin_Handled;

	return Plugin_Continue;
}

public Action OnGetMaxHealth(int client, int &health)
{
	return Plugin_Continue;
}

// Public Events

public Action CheckAlivePlayers(Handle timer)
{
	if(Enabled && VoteMode==Vote_None)
	{
		int reals, fakes;
		for(int i=1; i<=MaxClients; i++)
		{
			if(!IsValidClient(i) || Client[i].Status!=Status_Alive)
				continue;

			if(Client[i].Imposter)
			{
				fakes++;
			}
			else
			{
				reals++;
			}
		}

		if(reals <= fakes)
		{
			EndRound(3);
		}
		else if(!fakes)
		{
			EndRound(2);
		}
	}
	return Plugin_Continue;
}

public void UpdateListenOverrides()
{
	if(!Enabled)
		return;

	for(int client=1; client<=MaxClients; client++)
	{
		if(!IsValidClient(client, false))
			continue;

		bool blocked;
		#if defined _basecomm_included
		if(!blocked && BaseComm && BaseComm_IsClientMuted(client))
			blocked = true;
		#endif

		#if defined _sourcecomms_included
		if(!blocked && SourceComms && SourceComms_GetClientMuteType(client)>bNot)
			blocked = true;
		#endif

		int team = GetClientTeam(client);

		static float clientPos[3];
		GetEntPropVector(client, Prop_Send, "m_vecOrigin", clientPos);
		for(int target=1; target<=MaxClients; target++)
		{
			if(client == target)
			{
				SetListenOverride(target, client, Listen_Default);
				continue;
			}

			if(!IsValidClient(target))
				continue;

			bool muted = IsClientMuted(target, client);

			if(Client[client].Status==Status_Spec && team==view_as<int>(TFTeam_Spectator) && CheckCommandAccess(client, "sm_mute", ADMFLAG_CHAT))
			{
				Client[client].CanTalkTo[target] = true;
				SetListenOverride(target, client, (muted || blocked) ? Listen_No : Listen_Default);
			}
			else if(RoundMode != Round_Active)
			{
				Client[client].CanTalkTo[target] = !muted;
				SetListenOverride(target, client, (muted || blocked) ? Listen_No : Listen_Default);
			}
			else if(Client[client].Status != Status_Alive)
			{
				Client[client].CanTalkTo[target] = (!muted && Client[target].Status!=Status_Alive);
				SetListenOverride(target, client, (muted || blocked || Client[target].Status!=Status_Alive) ? Listen_No : Listen_Default);
			}
			else if(VoteMode != Vote_None)
			{
				Client[client].CanTalkTo[target] = !muted;
				SetListenOverride(target, client, (muted || blocked) ? Listen_No : Listen_Default);
			}
			else
			{
				Client[client].CanTalkTo[target] = false;
				SetListenOverride(target, client, Listen_No);
			}
		}
	}
}

void EndRound(int team)
{
	int entity = -1;
	while((entity=FindEntityByClassname(entity, "logic_relay")) != -1)
	{
		static char name[32];
		GetEntPropString(entity, Prop_Data, "m_iName", name, sizeof(name));
		if(StrEqual(name, "au_roundend", false))
		{
			switch(team)
			{
				case 2:
					AcceptEntityInput(entity, "FireUser1");

				case 3:
					AcceptEntityInput(entity, "FireUser2");

				default:
					AcceptEntityInput(entity, "FireUser3");
			}
			break;
		}
	}

	if(team == 2)
	{
		RoundMode = Round_CrewWin;
	}
	else if(team == 3)
	{
		RoundMode = Round_FakeWin;
	}

	entity = FindEntityByClassname(-1, "team_control_point_master");
	if(!IsValidEntity(entity))
	{
		entity = CreateEntityByName("team_control_point_master");
		DispatchSpawn(entity);
		AcceptEntityInput(entity, "Enable");
	}
	SetVariantInt(team);
	AcceptEntityInput(entity, "SetWinner");
}

void ShowDeathNotice(int[] clients, int count, int attacker, int victim, int assister, int weaponid, const char[] weapon, int damagebits, int damageflags)
{
	Event event = CreateEvent("player_death", true);
	if(!event)
		return;

	event.SetInt("userid", victim);
	event.SetInt("attacker", attacker);
	event.SetInt("assister", assister);
	event.SetInt("weaponid", weaponid);
	event.SetString("weapon", weapon);
	event.SetInt("damagebits", damagebits);
	event.SetInt("damage_flags", damageflags);
	for(int i; i<count; i++)
	{
		event.FireToClient(clients[i]);
	}
	event.Cancel();
}

bool AttemptGrabItem(int client)
{
	int entity = GetClientPointVisible(client);
	if(entity > MaxClients)
	{
		static char name[64];
		if(GetEntityClassname(entity, name, sizeof(name)))
		{
			if(!StrContains(name, "prop_dynamic"))
			{
				if(Client[client].Status != Status_Spec)
				{
					GetEntPropString(entity, Prop_Data, "m_iName", name, sizeof(name));
					if(!StrContains(name, "au_trigger", false))
					{
						if(Client[client].Imposter)
						{
							AcceptEntityInput(entity, Client[client].Status==Status_Alive ? "FireUser2" : "FireUser4", client, client);
						}
						else
						{
							AcceptEntityInput(entity, Client[client].Status==Status_Alive ? "FireUser1" : "FireUser3", client, client);
						}
						return true;
					}
				}
			}
			else if(StrEqual(name, "func_button"))
			{
				if(Client[client].Status == Status_Alive)
				{
					GetEntPropString(entity, Prop_Data, "m_iName", name, sizeof(name));
					if(!StrContains(name, "au_trigger", false))
					{
						AcceptEntityInput(entity, "Press", client, client);
						return true;
					}
				}
			}
		}
	}
	return false;
}

public Action CheckWaitingPlayers(Handle timer)
{
	if(RoundMode == Round_Waiting)
	{
		PrintTrainingStart();
		int count;
		bool first;
		static char buffer[256];
		for(int client=1; client<=MaxClients; client++)
		{
			if(!IsClientInGame(client) || GetClientTeam(client)<=view_as<int>(TFTeam_Spectator))
				continue;

			if(first)
			{
				Format(buffer, sizeof(buffer), "%s, %N", buffer, client);
			}
			else
			{
				first = GetClientName(client, buffer, sizeof(buffer));
			}

			count++;
			PrintTraining(client, true, "%T", "waiting", client);
		}

		PrintTrainingToAll(false, buffer);
		if(count > 3)
		{
			EndRound(0);
			RoundMode = Round_None;
		}
	}
	return Plugin_Continue;
}

bool CheckForBodies(int client)
{
	static float pos[3];
	GetClientEyePosition(client, pos);

	int entity = -1;
	while((entity=FindEntityByClassname2(entity, "tf_ragdoll")) != -1)
	{
		static char name[32];
		GetEntPropString(entity, Prop_Data, "m_iName", name, sizeof(name));
		if(!StrContains(name, "au_deadbody", false))
		{
			static float vec[3];
			GetEntPropVector(entity, Prop_Send, "m_vecRagdollOrigin", vec);
			if(GetVectorDistance(pos, vec) < Client[client].ViewRange)
				return true;
		}
	}
	return false;
}

void CleanBodies()
{
	int entity = -1;
	while((entity=FindEntityByClassname2(entity, "tf_ragdoll")) != -1)
	{
		static char name[32];
		GetEntPropString(entity, Prop_Data, "m_iName", name, sizeof(name));
		if(!StrContains(name, "au_deadbody", false))
		{
			DissolveRagdoll(entity);
			CreateTimer(5.0, Timer_RemoveEntity, EntIndexToEntRef(entity), TIMER_FLAG_NO_MAPCHANGE);
		}
	}
}

void StartMeeting(int client, bool emergency)
{
	if(VoteMode != Vote_None)
		return;

	CleanBodies();
	PrintTrainingStart(15.0);

	MenuVote.RemoveAllItems();
	MenuVote.ExitButton = false;

	int amount;
	int[] clients = new int[MaxClients];

	char buffer[128];
	for(int i=1; i<=MaxClients; i++)
	{
		Client[i].Vote = -1;
		if(!IsClientInGame(i))
			continue;

		if(Client[i].Status == Status_Dead)
			Client[i].Team = 3;

		if(IsPlayerAlive(i) && Client[i].Status!=Status_Spec)
		{
			TF2_RespawnPlayer(i);
			SetEntityMoveType(i, MOVETYPE_NONE);
		}

		if(Client[i].Status == Status_Alive)
		{
			FormatEx(buffer, sizeof(buffer), "%N (%s)", i, ClassNames[TF2_GetPlayerClass(i)]);
			MenuVote.AddItem("0", buffer, ITEMDRAW_DISABLED);
			clients[amount++] = i;
		}

		SetGlobalTransTarget(i);
		PrintTraining(i, true, "%t", emergency ? "emergency" : "reported");
		PrintTraining(i, false, "%t", emergency ? "emergency_desc" : "reported_desc", client);
	}

	for(int i; i<amount; i++)
	{
		SetGlobalTransTarget(clients[i]);
		MenuVote.SetTitle("%t", "vote_title");
		MenuVote.Display(clients[i], 15);
		CPrintToChat(clients[i], "%s%t", PREFIX, "vote_started");
	}

	if(TimerVote != INVALID_HANDLE)
		KillTimer(TimerVote);

	TimerVote = CreateTimer(15.0, Timer_Vote, 90, TIMER_FLAG_NO_MAPCHANGE);
	VoteMode = Vote_Wait; 
}

public Action Timer_Vote(Handle timer, int count)
{
	if(VoteMode != Vote_None)
	{
		if(VoteMode == Vote_Wait)
		{
			VoteMode = Vote_On;
			RebuildVote();
		}

		if(count)
		{
			PrintHintTextToAll("%t", "vote_ends", count);
			TimerVote = CreateTimer(1.0, Timer_Vote, count-1, TIMER_FLAG_NO_MAPCHANGE);
		}
		else
		{
			PrintHintTextToAll(" ");
			PrintToConsoleAll(" ");
			TimerVote = INVALID_HANDLE;
			int amount, votes[MAXTF2PLAYERS];
			int[] clients = new int[MaxClients];
			for(int i=1; i<=MaxClients; i++)
			{
				if(!IsClientInGame(i))
					continue;

				clients[amount++] = i;
				if(Client[i].Status!=Status_Alive || (Client[i].Vote && !IsValidClient(Client[i].Vote)))
					continue;

				votes[Client[i].Vote]++;
				if(Client[i].Vote)
				{
					PrintToConsoleAll("%t", "voted_for", i, Client[i].Vote);
				}
				else
				{
					PrintToConsoleAll("%t", "voted_skip", i);
				}
			}
			PrintToConsoleAll(" ");

			int winner, points;
			for(int i; i<=MaxClients; i++)
			{
				if(votes[i] < points)
					continue;

				if(votes[i] == points)
				{
					winner = -1;
				}
				else
				{
					winner = i;
				}

				points = votes[i];
			}

			SetHudTextParams(-1.0, -1.0, 5.0, 255, 255,  255, 255, 2, 2.0, _, 2.0);
			for(int i; i<amount; i++)
			{
				if(winner == -1)
				{
					ShowHudText(clients[i], 0, "%T", "result_tie", clients[i]);
				}
				else if(!winner)
				{
					ShowHudText(clients[i], 0, "%T", "result_skip", clients[i]);
				}
				else if(Client[winner].Imposter)
				{
					ShowHudText(clients[i], 0, "%T", "result_correct", clients[i], winner);
					if(winner!=clients[i] && Client[clients[i]].Vote==winner)
					{
						Client[clients[i]].Points++;
						if(!Client[clients[i]].Imposter)
							Client[clients[i]].StoredPoints -= 2;
					}
				}
				else
				{
					ShowHudText(clients[i], 0, "%T", "result_incorrect", clients[i], winner);
					if(winner!=clients[i] && Client[clients[i]].Vote==winner)
					{
						Client[clients[i]].Points--;
						if(Client[clients[i]].Imposter)
							Client[clients[i]].StoredPoints += 2;
					}
				}
			}

			if(winner > 0)
			{
				Client[winner].Team = 3;
				Client[winner].Status = Status_Dead;

				points = -1;
				while((points=FindEntityByClassname2(points, "info_target")) != -1)
				{
					static char buffer[64];
					GetEntPropString(points, Prop_Data, "m_iName", buffer, sizeof(buffer));
					if(GetInfoType(buffer, sizeof(buffer)) != Info_Kicked)
						continue;

					static float pos[3];
					GetEntPropVector(points, Prop_Send, "m_vecOrigin", pos);
					TeleportEntity(winner, pos, NULL_VECTOR, NULL_VECTOR);
					CreateTimer(6.0, Timer_EndVote, 0, TIMER_FLAG_NO_MAPCHANGE);
					break;
				}

				if(points == -1)
					CreateTimer(6.0, Timer_EndVote, GetClientUserId(winner), TIMER_FLAG_NO_MAPCHANGE);
			}
			else
			{
				CreateTimer(6.0, Timer_EndVote, 0, TIMER_FLAG_NO_MAPCHANGE);
			}
		}
	}
	return Plugin_Continue;
}

void RebuildVote()
{
	MenuVote.RemoveAllItems();
	MenuVote.ExitButton = true;

	char buffer[128], num[4];

	int amount;
	int[] clients = new int[MaxClients];
	for(int i=1; i<=MaxClients; i++)
	{
		if(!IsClientInGame(i) || Client[i].Status!=Status_Alive)
			continue;

		IntToString(i, num, sizeof(num));
		FormatEx(buffer, sizeof(buffer), "%N (%s)", i, ClassNames[TF2_GetPlayerClass(i)]);
		MenuVote.AddItem(num, buffer);
		clients[amount++] = i;
	}

	for(int i; i<amount; i++)
	{
		MenuVote.SetTitle("%T", "vote_title", clients[i]);
		MenuVote.Display(clients[i], MENU_TIME_FOREVER);
	}
}

public Action Timer_EndVote(Handle timer, int userid)
{
	VoteMode = Vote_None;
	int client = GetClientOfUserId(userid);
	if(client && !IsClientInGame(client))
		client = 0;

	int amount;
	int[] clients = new int[MaxClients];
	for(int i=1; i<=MaxClients; i++)
	{
		Client[i].KillIn = GetEngineTime()+15.0;
		if(!IsClientInGame(i))
			continue;

		SetEntityMoveType(i, MOVETYPE_WALK);
		clients[amount++] = i;
	}

	if(client)
	{
		for(int i; i<amount; i++)
		{
			if(Client[clients[i]].Vote == client)
				ShowDeathNotice(clients, amount, GetClientUserId(clients[i]), userid, 0, -1, "mantreads", DMG_CRIT, 0);
		}

		ForcePlayerSuicide(client);
		CreateTimer(0.1, Timer_DissolveRagdoll, userid, TIMER_FLAG_NO_MAPCHANGE);
	}

	KillEvent();
}

public int Handler_Vote(Menu menu, MenuAction action, int client, int choice)
{
	switch(action)
	{
		case MenuAction_Cancel:
		{
			if(choice == MenuCancel_Exit)
				Client[client].Vote = 0;
		}
		case MenuAction_Select:
		{
			char buffer[4];
			menu.GetItem(choice, buffer, sizeof(buffer));
			Client[client].Vote = StringToInt(buffer);
		}
	}
}

EntityEnum GetRelayType(int entity, int &id, int &info)
{
	static char name[64];
	GetEntPropString(entity, Prop_Data, "m_iName", name, sizeof(name));
	if(!StrContains(name, "au_vent", false))
	{
		return Relay_Vent;
	}
	else if(!StrContains(name, "au_meeting", false))
	{
		return Relay_Meeting;
	}
	else if(!StrContains(name, "au_roundend", false))
	{
		return Relay_RoundEnd;
	}
	else if(!StrContains(name, "au_", false))
	{	
		id = StringToInt(name[3])*10 + StringToInt(name[4]) - 1;
		if(StrContains(name, "_done", false) == 5)
		{
			return Relay_Done;
		}
		else if(StrContains(name, "_check", false) == 5)
		{
			return Relay_Check;
		}
		else if(StrContains(name, "_major", false) == 5)
		{
			strcopy(name, sizeof(name), name[12]);
			info = StringToInt(name);
			return Relay_Major;
		}
		else if(StrContains(name, "_menu", false) == 5)
		{
			strcopy(name, sizeof(name), name[11]);
			info = StringToInt(name);
			return Relay_Menu;
		}
	}
	return Ent_Unknown;
}

EntityEnum GetInfoType(char[] name, int length, int &id=0, int &info=0)
{
	if(!StrContains(name, "au_vent", false))
	{
		return Info_Vent;
	}
	else if(!StrContains(name, "au_", false))
	{
		id = StringToInt(name[3])*10 + StringToInt(name[4]) - 1;
		if(StrContains(name, "_count", false) == 5)
		{
			strcopy(name, length, name[12]);
			info = StringToInt(name);
			return Info_Count;
		}

		info = strcopy(name, length, name[6]);
		return Info_Name;
	}
	return Ent_Unknown;
}

void TurnIntoGhost(int client)
{
	TF2_AddCondition(client, TFCond_HalloweenGhostMode);
	TF2_AddCondition(client, TFCond_StealthedUserBuffFade);
	ChangeClientTeamEx(client, 3);
}

int GetFog()
{
}

int CreateFog(float range, bool imposter)
{
	int entity = CreateEntityByName("env_fog_controller");
	if(IsValidEntity(entity)) 
	{
		DispatchKeyValue(entity, "targetname", imposter ? "au_fog_imp" : "au_fog_crew");
		DispatchKeyValue(entity, "fogenable", "1");
		DispatchKeyValue(entity, "spawnflags", "1");
		DispatchKeyValue(entity, "fogblend", "0");
		DispatchKeyValue(entityentity, "fogcolor", "0 0 0");
		DispatchKeyValue(entity, "fogcolor2", "0 0 0");
		DispatchKeyValueFloat(entity, "fogstart", range);
		DispatchKeyValueFloat(entity, "fogend", range*1.1);
		DispatchKeyValueFloat(entity, "fogmaxdensity", 1.0);
		DispatchSpawn(entity);

		AcceptEntityInput(entity, "TurnOn");
	}
}

public bool TraceRayPlayerOnly(int client, int mask, any data)
{
	return (client!=data && IsValidClient(client) && IsValidClient(data));
}

public bool TraceWallsOnly(int entity, int contentsMask)
{
	return false;
}

public bool Trace_DontHitEntity(int entity, int mask, any data)
{
	return (entity!=data);
}

// DHook Events

public MRESReturn DHook_RoundRespawn()
{
	if(Enabled)
	{
		Crewmates = 0;
		Imposters = 0;
		EventIn = GetEngineTime()+15.0;

		ArrayList list = new ArrayList();
		for(int client; client<MAXTF2PLAYERS; client++)
		{
			Client[client].Imposter = false;
			Client[client].KillIn = EventIn;
			if(!IsValidClient(client))
				continue;

			if(GetClientTeam(client) <= view_as<int>(TFTeam_Spectator))
			{
				PrintTraining(client, true, "%T", "you_spectate", client);
				Client[client].ViewRange = -1.0;
				Client[client].Status = Status_Spec;
				Client[client].Team = 1;
				continue;
			}

			Crewmates++;
			PrintTraining(client, true, "%T", "you_crewmate", client);
			Client[client].ViewRange = 400.0;
			Client[client].Team = 2;
			Client[client].Status = Status_Alive;
			ChangeClientTeamEx(client, view_as<int>(TFTeam_Red));
			list.Push(client);
		}

		int total = list.Length;
		if(total < 3)
		{
			for(int client; client<MAXTF2PLAYERS; client++)
			{
				Client[client].Status = Status_Spec;
			}

			RoundMode = Round_Waiting;
		}
		else
		{
			RoundMode = Round_Active;

			int amount = total/5;
			if(amount < 1)
				amount = 1;

			Crewmates -= amount;
			Imposters = amount;
			PrintTrainingStart(6.0);

			for(int i; i<total; i++)
			{
				int client = list.Get(i);
				PrintTraining(client, false, "%T", "among_us", client, amount);
			}

			int count;
			static char buffer[256];
			int[] fakes = new int[amount];
			for(int i; i<amount; i++)
			{
				int choosen = GetRandomInt(0, --total);
				int client = list.Get(choosen);

				if(count)
				{
					Format(buffer, sizeof(buffer), "%s, %N", buffer, client);
				}
				else
				{
					GetClientName(client, buffer, sizeof(buffer));
				}

				fakes[count++] = client;
				Client[client].Imposter = true;
				Client[client].ViewRange = 600.0;
				PrintTraining(client, true, "%T", "you_imposter", client);
				list.Erase(choosen);
			}

			for(int i; i<count; i++)
			{
				PrintTraining(fakes[i], false, "%T%s", "your_allies", fakes[i], buffer);
			}
		}
		delete list;
	}
	return MRES_Ignored;
}

public MRESReturn DHook_SetWinningTeam(Handle params)
{
	if(Enabled)
		return MRES_Supercede;

	DHookSetParam(params, 4, false);
	return MRES_ChangedOverride;
}

public MRESReturn DHook_IsInTraining(Address pointer, Handle returnVal)
{
	if(!TrainingOn)
		return MRES_Ignored;

	//Trick the client into thinking the training mode is enabled.
	DHookSetReturn(returnVal, false);
	return MRES_Supercede;
}

public MRESReturn DHook_GetGameType(Address pointer, Handle returnVal)
{
	if(!TrainingOn)
		return MRES_Ignored;

	DHookSetReturn(returnVal, 0);
	return MRES_Supercede;
}

public MRESReturn DHook_Supercede(int client, Handle params)
{
	return Enabled ? MRES_Supercede : MRES_Ignored;
}

// SendProp

public Action SendProp_OnAlive(int entity, const char[] propname, int &value, int client) 
{
	if(Enabled)
	{
		switch(RoundMode)
		{
			case Round_Active:
			{
				value = 1;
				return Plugin_Changed;
			}
			case Round_CrewWin, Round_FakeWin:
			{
				value = Client[client].Status==Status_Alive ? 1 : 0;
				return Plugin_Changed;
			}
		}
	}
	return Plugin_Continue;
}

public Action SendProp_OnTeam(int entity, const char[] propname, int &value, int client) 
{
	if(!Enabled || RoundMode<=Round_Waiting)
		return Plugin_Continue;

	value = Client[client].Team;
	return Plugin_Changed;
}

public Action SendProp_OnScore(int entity, const char[] propname, int &value, int client) 
{
	if(!Enabled)
		return Plugin_Continue;

	value = Client[client].Points;
	return Plugin_Changed;
}

// Thirdparty

public Action OnStomp()
{
	return Enabled ? Plugin_Handled : Plugin_Continue;
}

// Ragdoll Effects

//public void CreateSpecialDeath(int userid)
void CreateSpecialDeath(int client)
{
/*	int client = GetClientOfUserId(userid);
	if(!client || !IsClientInGame(client))
		return;*/

	float time = 0.4;

	static float pos[3];
	GetEntPropVector(client, Prop_Send, "m_vecOrigin", pos);

	char model[PLATFORM_MAX_PATH];
	GetEntPropString(client, Prop_Data, "m_ModelName", model, sizeof(model));

	int team = GetClientTeam(client);
	TFClassType class = TF2_GetPlayerClass(client);
	if(class!=TFClass_Pyro && class!=TFClass_Unknown)
	{
		int entity = CreateEntityByName("prop_dynamic_override");
		if(IsValidEntity(entity))
		{
			//RequestFrame(RemoveRagdoll, userid);

			int special = (class==TFClass_Engineer || class==TFClass_DemoMan || class==TFClass_Heavy) ? 1 : 0;
			TeleportEntity(entity, pos, NULL_VECTOR, NULL_VECTOR);
			{
				char skin[2];
				IntToString(team-2, skin, sizeof(skin));
				DispatchKeyValue(entity, "skin", skin);
			}
			DispatchKeyValue(entity, "model", model);
			DispatchKeyValue(entity, "DefaultAnim", FireDeath[special]);	
			{
				float angles[3];
				GetClientEyeAngles(client, angles);
				angles[0] = 0.0;
				angles[2] = 0.0;
				DispatchKeyValueVector(entity, "angles", angles);
			}
			DispatchSpawn(entity);
				
			SetVariantString(FireDeath[special]);
			AcceptEntityInput(entity, "SetAnimation");

			/*SetVariantString("OnAnimationDone !self:KillHierarchy::0.0:1");
			AcceptEntityInput(entity, "AddOutput");
			{
				char output[128];
				FormatEx(output, sizeof(output), "OnUser1 !self:KillHierarchy::%f:1", FireDeathTimes[class]+0.1); 
				SetVariantString(output);
				AcceptEntityInput(entity, "AddOutput");
			}
			SetVariantString("");
			AcceptEntityInput(entity, "FireUser1");*/

			time = FireDeathTimes[class]-0.4;
			CreateTimer(FireDeathTimes[class], Timer_RemoveEntity, EntIndexToEntRef(entity));
		}
	}

	DataPack pack;
	CreateDataTimer(time, CreateRagdoll, pack, TIMER_FLAG_NO_MAPCHANGE);
	pack.WriteCell(GetClientUserId(client));
	pack.WriteFloat(pos[0]);
	pack.WriteFloat(pos[1]);
	pack.WriteFloat(pos[2]);
	pack.WriteCell(team);
	pack.WriteCell(class);
	pack.WriteString(model);
}

public Action CreateRagdoll(Handle timer, DataPack pack)
{
	pack.Reset();
	int client = GetClientOfUserId(pack.ReadCell());
	if(!client || !IsClientInGame(client))
		return Plugin_Continue;

	int entity = CreateEntityByName("tf_ragdoll");
	if(!IsValidEntity(entity))
		return Plugin_Continue;

	{
		float vec[3];
		/*vec[0] = -18000.552734;
		vec[1] = -8000.552734;
		vec[2] = 8000.552734;
		SetEntPropVector(entity, Prop_Send, "m_vecRagdollVelocity", vec);
		SetEntPropVector(entity, Prop_Send, "m_vecForce", vec);*/

		vec[0] = pack.ReadFloat();
		vec[1] = pack.ReadFloat();
		vec[2] = pack.ReadFloat();
		TeleportEntity(entity, vec, NULL_VECTOR, NULL_VECTOR);
		SetEntPropVector(entity, Prop_Send, "m_vecRagdollOrigin", vec);
	}

	SetEntProp(entity, Prop_Send, "m_iPlayerIndex", client);
	SetEntProp(entity, Prop_Send, "m_iTeam", pack.ReadCell());
	SetEntProp(entity, Prop_Send, "m_iClass", pack.ReadCell());
	SetEntProp(entity, Prop_Send, "m_nForceBone", 1);

	static char model[PLATFORM_MAX_PATH];
	pack.ReadString(model, sizeof(model));
	DispatchKeyValue(entity, "model", model);
	DispatchKeyValue(entity, "targetname", "au_deadbody");
	DispatchSpawn(entity);

	//CreateTimer(15.0, Timer_RemoveEntity, EntIndexToEntRef(entity), TIMER_FLAG_NO_MAPCHANGE);
	return Plugin_Continue;
}

public void RemoveRagdoll(int userid)
{
	int client = GetClientOfUserId(userid);
	if(!client || !IsClientInGame(client))
		return;

	int entity = GetEntPropEnt(client, Prop_Send, "m_hRagdoll");
	if(IsValidEdict(entity))
		AcceptEntityInput(entity, "kill");
}

// Stocks

stock int AttachParticle(int entity, char[] particleType, float offset=0.0, bool attach=true)
{
	int particle = CreateEntityByName("info_particle_system");

	char targetName[128];
	float position[3];
	GetEntPropVector(entity, Prop_Send, "m_vecOrigin", position);
	position[2] += offset;
	TeleportEntity(particle, position, NULL_VECTOR, NULL_VECTOR);

	Format(targetName, sizeof(targetName), "target%d", entity);
	DispatchKeyValue(entity, "targetname", targetName);

	DispatchKeyValue(particle, "targetname", "tf2particle");
	DispatchKeyValue(particle, "parentname", targetName);
	DispatchKeyValue(particle, "effect_name", particleType);
	DispatchSpawn(particle);
	SetVariantString(targetName);
	if(attach)
	{
		AcceptEntityInput(particle, "SetParent", particle, particle, 0);
		SetEntPropEnt(particle, Prop_Send, "m_hOwnerEntity", entity);
	}
	ActivateEntity(particle);
	AcceptEntityInput(particle, "start");
	return particle;
}

public Action Timer_RemoveEntity(Handle timer, any entid)
{
	int entity = EntRefToEntIndex(entid);
	if(IsValidEdict(entity) && entity>MaxClients)
	{
		TeleportEntity(entity, OFF_THE_MAP, NULL_VECTOR, NULL_VECTOR); // send it away first in case it feels like dying dramatically
		AcceptEntityInput(entity, "Kill");
	}
}

public Action Timer_DissolveRagdoll(Handle timer, any userid)
{
	int client = GetClientOfUserId(userid);
	if(client && IsClientInGame(client))
	{
		int ragdoll = GetEntPropEnt(client, Prop_Send, "m_hRagdoll");
		if(IsValidEntity(ragdoll))
			DissolveRagdoll(ragdoll);
	}
}

int DissolveRagdoll(int ragdoll)
{
	int dissolver = CreateEntityByName("env_entity_dissolver");
	if(dissolver == -1)
		return;

	DispatchKeyValue(dissolver, "dissolvetype", "0");
	DispatchKeyValue(dissolver, "magnitude", "200");
	DispatchKeyValue(dissolver, "target", "!activator");

	AcceptEntityInput(dissolver, "Dissolve", ragdoll);
	AcceptEntityInput(dissolver, "Kill");
}

stock int CheckRoundState()
{
	switch(GameRules_GetRoundState())
	{
		case RoundState_Init, RoundState_Pregame:
		{
			return -1;
		}
		case RoundState_StartGame, RoundState_Preround:
		{
			return 0;
		}
		case RoundState_RoundRunning, RoundState_Stalemate:  //Oh Valve.
		{
			return 1;
		}
	}
	return 2;
}

stock int GetClientPointVisible(int iClient, float flDistance = 100.0)
{
	float vecOrigin[3], vecAngles[3], vecEndOrigin[3];
	GetClientEyePosition(iClient, vecOrigin);
	GetClientEyeAngles(iClient, vecAngles);
	
	Handle hTrace = TR_TraceRayFilterEx(vecOrigin, vecAngles, MASK_ALL, RayType_Infinite, Trace_DontHitEntity, iClient);
	TR_GetEndPosition(vecEndOrigin, hTrace);
	
	int iReturn = -1;
	int iHit = TR_GetEntityIndex(hTrace);
	
	if (TR_DidHit(hTrace) && iHit != iClient && GetVectorDistance(vecOrigin, vecEndOrigin) < flDistance)
		iReturn = iHit;
	
	delete hTrace;
	return iReturn;
}

stock void SpawnPickup(int iClient, const char[] sClassname)
{
	float vecOrigin[3];
	GetClientAbsOrigin(iClient, vecOrigin);
	vecOrigin[2] += 16.0;
	
	int iEntity = CreateEntityByName(sClassname);
	DispatchKeyValue(iEntity, "OnPlayerTouch", "!self,Kill,,0,-1");
	if (DispatchSpawn(iEntity))
	{
		SetEntProp(iEntity, Prop_Send, "m_iTeamNum", 0, 4);
		TeleportEntity(iEntity, vecOrigin, NULL_VECTOR, NULL_VECTOR);
		CreateTimer(0.15, Timer_RemoveEntity, EntIndexToEntRef(iEntity));
	}
}

stock void DoOverlay(int client, const char[] overlay)
{
	int flags = GetCommandFlags("r_screenoverlay");
	SetCommandFlags("r_screenoverlay", flags & ~FCVAR_CHEAT);
	if(overlay[0])
	{
		ClientCommand(client, "r_screenoverlay \"%s\"", overlay);
	}
	else
	{
		ClientCommand(client, "r_screenoverlay off");
	}
	SetCommandFlags("r_screenoverlay", flags);
}

stock bool IsClassname(int iEntity, const char[] sClassname)
{
	if (iEntity > MaxClients)
	{
		char sClassname2[256];
		GetEntityClassname(iEntity, sClassname2, sizeof(sClassname2));
		return (StrEqual(sClassname2, sClassname));
	}
	
	return false;
}

stock float fabs(float x)
{
	return x<0 ? -x : x;
}

stock float fixAngle(float angle)
{
	int i;
	for(; i<11 && angle<-180; i++)
	{
		angle += 360.0;
	}
	for(; i<11 && angle>180; i++)
	{
		angle -= 360.0;
	}	
	return angle;
}

stock float GetVectorAnglesTwoPoints(const float startPos[3], const float endPos[3], float angles[3])
{
	static float tmpVec[3];
	tmpVec[0] = endPos[0] - startPos[0];
	tmpVec[1] = endPos[1] - startPos[1];
	tmpVec[2] = endPos[2] - startPos[2];
	GetVectorAngles(tmpVec, angles);
}

stock bool IsValidClient(int client, bool replaycheck=true)
{
	if(client<=0 || client>MaxClients)
		return false;

	if(!IsClientInGame(client))
		return false;

	if(GetEntProp(client, Prop_Send, "m_bIsCoaching"))
		return false;

	if(replaycheck && (IsClientSourceTV(client) || IsClientReplay(client)))
		return false;

	return true;
}

stock bool IsInvuln(int client)
{
	if(!IsValidClient(client))
		return true;

	return (TF2_IsPlayerInCondition(client, TFCond_Ubercharged) ||
		TF2_IsPlayerInCondition(client, TFCond_UberchargedCanteen) ||
		TF2_IsPlayerInCondition(client, TFCond_UberchargedHidden) ||
		TF2_IsPlayerInCondition(client, TFCond_UberchargedOnTakeDamage) ||
		TF2_IsPlayerInCondition(client, TFCond_Bonked) ||
		TF2_IsPlayerInCondition(client, TFCond_HalloweenGhostMode) ||
		!GetEntProp(client, Prop_Data, "m_takedamage"));
}

stock int FindEntityByClassname2(int startEnt, const char[] classname)
{
	while(startEnt>-1 && !IsValidEntity(startEnt))
	{
		startEnt--;
	}
	return FindEntityByClassname(startEnt, classname);
}

stock int GetOwnerLoop(int entity)
{
	int owner = GetEntPropEnt(entity, Prop_Send, "m_hOwnerEntity");
	if(owner>0 && owner!=entity)
		return GetOwnerLoop(owner);

	return entity;
}

stock void SetAmmo(int client, int weapon, int ammo=-1, int clip=-1)
{
	if(IsValidEntity(weapon))
	{
		if(clip > -1)
			SetEntProp(weapon, Prop_Data, "m_iClip1", clip);

		int ammoType = (ammo>-1 ? GetEntProp(weapon, Prop_Send, "m_iPrimaryAmmoType") : -1);
		if(ammoType != -1)
			SetEntProp(client, Prop_Data, "m_iAmmo", ammo, _, ammoType);
	}
}

stock void TF2_RefillWeaponAmmo(int client, int weapon)
{
	int ammotype = GetEntProp(weapon, Prop_Send, "m_iPrimaryAmmoType");
	if (ammotype > -1)
		GivePlayerAmmo(client, 9999, ammotype, true);
}

stock void TF2_SetWeaponAmmo(int client, int weapon, int ammo)
{
	int ammotype = GetEntProp(weapon, Prop_Send, "m_iPrimaryAmmoType");
	if (ammotype > -1)
		SetEntProp(client, Prop_Send, "m_iAmmo", ammo, _, ammotype);
}

stock int TF2_GetWeaponAmmo(int client, int weapon)
{
	int ammotype = GetEntProp(weapon, Prop_Send, "m_iPrimaryAmmoType");
	if (ammotype > -1)
		return GetEntProp(client, Prop_Send, "m_iAmmo", _, ammotype);
	
	return -1;
}

stock void SetSpeed(int client, float speed)
{
	SetEntPropFloat(client, Prop_Data, "m_flMaxspeed", speed);
}

stock void FadeMessage(int client, int arg1, int arg2, int arg3, int arg4=255, int arg5=255, int arg6=255, int arg7=255)
{
	Handle msg = StartMessageOne("Fade", client);
	BfWriteShort(msg, arg1);
	BfWriteShort(msg, arg2);
	BfWriteShort(msg, arg3);
	BfWriteByte(msg, arg4);
	BfWriteByte(msg, arg5);
	BfWriteByte(msg, arg6);
	BfWriteByte(msg, arg7);
	EndMessage();
}

stock void PrintKeyHintText(int client, const char[] format, any ...)
{
	Handle userMessage = StartMessageOne("KeyHintText", client);
	if(userMessage == INVALID_HANDLE)
		return;

	char buffer[256];
	SetGlobalTransTarget(client);
	VFormat(buffer, sizeof(buffer), format, 3);

	if(GetFeatureStatus(FeatureType_Native, "GetUserMessageType")==FeatureStatus_Available && GetUserMessageType()==UM_Protobuf)
	{
		PbSetString(userMessage, "hints", buffer);
	}
	else
	{
		BfWriteByte(userMessage, 1); 
		BfWriteString(userMessage, buffer); 
	}
	
	EndMessage();
}

stock void ModelIndexToString(int index, char[] model, int size)
{
	int table = FindStringTable("modelprecache");
	ReadStringTable(table, index, model, size);
}

stock int GiveFists(int client)
{
	TF2_RemoveAllWeapons(client);

	static char buffer[64];
	TFClassType class = TF2_GetPlayerClass(client);
	switch(class)
	{
		case TFClass_Scout:	strcopy(buffer, sizeof(buffer), "tf_weapon_bat");
		case TFClass_Pyro:	strcopy(buffer, sizeof(buffer), "tf_weapon_fireaxe");
		case TFClass_DemoMan:	strcopy(buffer, sizeof(buffer), "tf_weapon_bottle");
		case TFClass_Heavy:	strcopy(buffer, sizeof(buffer), "tf_weapon_fists");
		case TFClass_Engineer:	strcopy(buffer, sizeof(buffer), "tf_weapon_wrench");
		case TFClass_Medic:	strcopy(buffer, sizeof(buffer), "tf_weapon_bonesaw");
		case TFClass_Sniper:	strcopy(buffer, sizeof(buffer), "tf_weapon_club");
		default:		strcopy(buffer, sizeof(buffer), "tf_weapon_shovel");
	}

	Handle weapon = TF2Items_CreateItem(OVERRIDE_ALL|FORCE_GENERATION|PRESERVE_ATTRIBUTES);
	if(weapon == INVALID_HANDLE)
		return -1;

	TF2Items_SetClassname(weapon, buffer);
	TF2Items_SetItemIndex(weapon, 5);
	TF2Items_SetLevel(weapon, 1);
	TF2Items_SetQuality(weapon, 0);
	TF2Items_SetAttribute(weapon, 0, 1, 0.0);

	float value = 1.0;
	switch(class)
	{
		case TFClass_Scout:	value *= 0.75;
		case TFClass_Soldier:	value *= 1.25;
		case TFClass_DemoMan:	value *= 1.071429;
		case TFClass_Heavy:	value *= 1.304348;
		case TFClass_Medic:	value *= 0.9375;
		case TFClass_Spy:	value *= 0.9375;
	}

	TF2Items_SetAttribute(weapon, 1, 442, value);
	if(class == TFClass_Scout)
	{
		TF2Items_SetAttribute(weapon, 2, 49, 1.0);
		TF2Items_SetNumAttributes(weapon, 3);
	}
	else
	{
		TF2Items_SetNumAttributes(weapon, 2);
	}

	int entity = TF2Items_GiveNamedItem(client, weapon);
	delete weapon;

	if(entity > MaxClients)
	{
		EquipPlayerWeapon(client, entity);
		SetEntPropFloat(entity, Prop_Send, "m_flNextPrimaryAttack", FAR_FUTURE);
		SetEntityRenderMode(entity, RENDER_TRANSCOLOR);
		SetEntityRenderColor(entity, 255, 255, 255, 0);
		SetEntPropEnt(client, Prop_Send, "m_hActiveWeapon", entity);
	}
	return entity;
}

stock int SpawnWeapon(int client, char[] name, int index, int level, int qual, const char[] att, bool visible=true, bool preserve=false)
{
	/*if(StrEqual(name, "saxxy", false))	// if "saxxy" is specified as the name, replace with appropiate name
	{ 
		switch(TF2_GetPlayerClass(client))
		{
			case TFClass_Scout:	ReplaceString(name, 64, "saxxy", "tf_weapon_bat", false);
			case TFClass_Pyro:	ReplaceString(name, 64, "saxxy", "tf_weapon_fireaxe", false);
			case TFClass_DemoMan:	ReplaceString(name, 64, "saxxy", "tf_weapon_bottle", false);
			case TFClass_Heavy:	ReplaceString(name, 64, "saxxy", "tf_weapon_fists", false);
			case TFClass_Engineer:	ReplaceString(name, 64, "saxxy", "tf_weapon_wrench", false);
			case TFClass_Medic:	ReplaceString(name, 64, "saxxy", "tf_weapon_bonesaw", false);
			case TFClass_Sniper:	ReplaceString(name, 64, "saxxy", "tf_weapon_club", false);
			case TFClass_Spy:	ReplaceString(name, 64, "saxxy", "tf_weapon_knife", false);
			default:		ReplaceString(name, 64, "saxxy", "tf_weapon_shovel", false);
		}
	}
	else if(StrEqual(name, "tf_weapon_shotgun", false))	// If using tf_weapon_shotgun for Soldier/Pyro/Heavy/Engineer
	{
		switch(TF2_GetPlayerClass(client))
		{
			case TFClass_Pyro:	ReplaceString(name, 64, "tf_weapon_shotgun", "tf_weapon_shotgun_pyro", false);
			case TFClass_Heavy:	ReplaceString(name, 64, "tf_weapon_shotgun", "tf_weapon_shotgun_hwg", false);
			case TFClass_Engineer:	ReplaceString(name, 64, "tf_weapon_shotgun", "tf_weapon_shotgun_primary", false);
			default:		ReplaceString(name, 64, "tf_weapon_shotgun", "tf_weapon_shotgun_soldier", false);
		}
	}*/

	Handle hWeapon;
	if(preserve)
	{
		hWeapon = TF2Items_CreateItem(OVERRIDE_ALL|FORCE_GENERATION|PRESERVE_ATTRIBUTES);
	}
	else
	{
		hWeapon = TF2Items_CreateItem(OVERRIDE_ALL|FORCE_GENERATION);
	}

	if(hWeapon == INVALID_HANDLE)
		return -1;

	TF2Items_SetClassname(hWeapon, name);
	TF2Items_SetItemIndex(hWeapon, index);
	TF2Items_SetLevel(hWeapon, level);
	TF2Items_SetQuality(hWeapon, qual);
	char atts[32][32];
	int count = ExplodeString(att, ";", atts, 32, 32);

	if(count % 2)
		--count;

	if(count > 0)
	{
		TF2Items_SetNumAttributes(hWeapon, count/2);
		int i2;
		for(int i; i<count; i+=2)
		{
			int attrib = StringToInt(atts[i]);
			if(!attrib)
			{
				LogError("Bad weapon attribute passed: %s ; %s", atts[i], atts[i+1]);
				delete hWeapon;
				return -1;
			}

			TF2Items_SetAttribute(hWeapon, i2, attrib, StringToFloat(atts[i+1]));
			i2++;
		}
	}
	else
	{
		TF2Items_SetNumAttributes(hWeapon, 0);
	}

	int entity = TF2Items_GiveNamedItem(client, hWeapon);
	delete hWeapon;
	if(entity == -1)
		return -1;

	EquipPlayerWeapon(client, entity);

	if(visible)
	{
		SetEntProp(entity, Prop_Send, "m_bValidatedAttachedEntity", 1);
	}
	else
	{
		SetEntProp(entity, Prop_Send, "m_iWorldModelIndex", -1);
		SetEntPropFloat(entity, Prop_Send, "m_flModelScale", 0.001);
		SetEntProp(entity, Prop_Send, "m_bValidatedAttachedEntity", 0);
	}
	return entity;
}

stock int PrecacheModelEx(const char[] model, bool preload=false)
{
	static char buffer[PLATFORM_MAX_PATH];
	strcopy(buffer, sizeof(buffer), model);
	ReplaceString(buffer, sizeof(buffer), ".mdl", "");

	int table = FindStringTable("downloadables");
	bool save = LockStringTables(false);
	char buffer2[PLATFORM_MAX_PATH];
	static const char fileTypes[][] = {"dx80.vtx", "dx90.vtx", "mdl", "phy", "sw.vtx", "vvd"};
	for(int i; i<sizeof(fileTypes); i++)
	{
		FormatEx(buffer2, sizeof(buffer2), "%s.%s", buffer, fileTypes[i]);
		if(FileExists(buffer2))
			AddToStringTable(table, buffer2);
	}
	LockStringTables(save);

	return PrecacheModel(model, preload);
}

stock int PrecacheSoundEx(const char[] sound, bool preload=false)
{
	char buffer[PLATFORM_MAX_PATH];
	FormatEx(buffer, sizeof(buffer), "sound/%s", sound);
	ReplaceStringEx(buffer, sizeof(buffer), "#", "");
	if(FileExists(buffer))
		AddFileToDownloadsTable(buffer);

	return PrecacheSound(sound, preload);
}

stock void ChangeClientTeamEx(int client, int newTeam)
{
	if(SDKTeamAddPlayer==null || SDKTeamRemovePlayer==null)
		return;

	int currentTeam = GetEntProp(client, Prop_Send, "m_iTeamNum");

	// Safely swap team
	int team = MaxClients+1;
	while((team=FindEntityByClassname(team, "tf_team")) != -1)
	{
		int entityTeam = GetEntProp(team, Prop_Send, "m_iTeamNum");
		if(entityTeam == currentTeam)
		{
			SDKCall(SDKTeamRemovePlayer, team, client);
		}
		else if(entityTeam == newTeam)
		{
			SDKCall(SDKTeamAddPlayer, team, client);
		}
	}
	SetEntProp(client, Prop_Send, "m_iTeamNum", newTeam);
}

stock void PrintTrainingStart(float duration=0.0)
{
	if(!TrainingOn)
	{
		TrainingOn = true;
		GameRules_SetProp("m_bIsInTraining", true, 1, _, true);
		GameRules_SetProp("m_bIsTrainingHUDVisible", true, 1, _, true);

		int entity = FindEntityByClassname(-1, "tf_gamerules");
		if(entity > MaxClients)
		{
			SetEntData(entity, 2122, 1, 4, true);
			SetEntData(entity, 2126, 1, 4, true);
		}
	}

	if(TimerTraining != INVALID_HANDLE)
		KillTimer(TimerTraining);

	if(duration > 0)
	{
		TimerTraining = CreateTimer(duration, TrainingMessageOff, _, TIMER_FLAG_NO_MAPCHANGE);
	}
	else
	{
		TimerTraining = INVALID_HANDLE;
	}
}

stock bool PrintTraining(int client, bool title, const char[] message, any ...)
{
	BfWrite msg = view_as<BfWrite>(StartMessageOne(title ? "TrainingObjective" : "TrainingMsg", client));
	if(msg == INVALID_HANDLE)
		return false;

	static char buffer[256];
	VFormat(buffer, sizeof(buffer), message, 4);

	msg.WriteString(buffer);
	EndMessage();
	return true;
}

stock bool PrintTrainingToAll(bool title, const char[] message)
{
	BfWrite msg = view_as<BfWrite>(StartMessageAll(title ? "TrainingObjective" : "TrainingMsg"));
	if(msg == INVALID_HANDLE)
		return false;

	msg.WriteString(message);
	EndMessage();
	return true;
}

public Action TrainingMessageOff(Handle timer)
{
	TrainingOn = false;
	GameRules_SetProp("m_bIsInTraining", false, 1, _, true);
	GameRules_SetProp("m_bIsTrainingHUDVisible", false, 1, _, true);
	TimerTraining = INVALID_HANDLE;
	return Plugin_Continue;
}

stock void Debug(const char[] message, any ...)
{
	#if defined DEBUG
	static char buffer[512];
	VFormat(buffer, sizeof(buffer), message, 2);
	PrintToConsoleAll("DEBUG: %s", buffer);
	PrintToServer("DEBUG: %s", buffer);
	#endif
}

#file "Among Fortress"