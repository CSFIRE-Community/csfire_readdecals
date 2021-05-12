#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>

#define PLUGIN_VERSION "1.5"

#define READ	0
#define LIST	1

#define COLOR_DEFAULT	0x01
#define COLOR_GREEN		0x04

public Plugin myinfo =  {
	name = "Read Map Decals", 
	author = "Berni, Stingbyte, SM9();, DRANIX",
	description = "Heavily stripped down version of the original map decals plugin made by berni.", 
	version = PLUGIN_VERSION, 
	url = "https://csfire.gg/"
}

Handle md_version = INVALID_HANDLE;
Handle md_maxdis = INVALID_HANDLE;
Handle md_pos = INVALID_HANDLE;

Handle adt_decal_names = INVALID_HANDLE;
Handle adt_decal_paths = INVALID_HANDLE;
Handle adt_decal_precache = INVALID_HANDLE;
Handle adt_decal_id = INVALID_HANDLE;
Handle adt_decal_position = INVALID_HANDLE;

char mapName[256];
char path_decals[PLATFORM_MAX_PATH];
char path_mapdecals[PLATFORM_MAX_PATH];

public void OnPluginStart() {
	
	md_version = CreateConVar("md_version", PLUGIN_VERSION, "Map Decals plugin version", FCVAR_DONTRECORD | FCVAR_NOTIFY);
	SetConVarString(md_version, PLUGIN_VERSION);
	
	md_maxdis = CreateConVar("md_decal_dista", "50.0", "How far away from the Decals position it will be traced to and check distance to prevent painting a Decal over another");
	md_pos = CreateConVar("md_decal_printpos", "1", "Turns on/off printing out of decal positions");

	adt_decal_names = CreateArray(64);
	adt_decal_paths = CreateArray(PLATFORM_MAX_PATH);
	adt_decal_precache = CreateArray();
	adt_decal_id = CreateArray();
	adt_decal_position = CreateArray(3);

}

public void OnMapStart() {
	
	GetCurrentMap(mapName, sizeof(mapName));
	GetMapDisplayName(mapName, mapName, sizeof(mapName));
	
	BuildPath(Path_SM, path_decals, sizeof(path_decals), "configs/map-decals/decals.cfg");
	BuildPath(Path_SM, path_mapdecals, sizeof(path_mapdecals), "configs/map-decals/maps/%s.cfg", mapName);
	
	ReadDecals(-1, READ);
	
}

public void OnMapEnd() {
	
	ClearArray(adt_decal_names);
	ClearArray(adt_decal_paths);
	ClearArray(adt_decal_precache);
	
	ClearArray(adt_decal_id);
	ClearArray(adt_decal_position);
}

public void OnClientPostAdminCheck(int client) {
	
	float position[3];
	int id;
	int precache;
	
	int size = GetArraySize(adt_decal_id);
	for (int i = 0; i < size; ++i) {
		id = GetArrayCell(adt_decal_id, i);
		precache = GetArrayCell(adt_decal_precache, id);
		GetArrayArray(adt_decal_position, i, view_as<int>(position));
		TE_SetupBSPDecal(position, 0, precache);
		TE_SendToClient(client);
	}
}

public bool ReadDecals(int client, int mode) {
	
	char buffer[PLATFORM_MAX_PATH];
	char file[PLATFORM_MAX_PATH];
	char download[PLATFORM_MAX_PATH];
	Handle kv;
	Handle vtf;
	
	if (mode == READ) {
		
		kv = CreateKeyValues("Decals");
		FileToKeyValues(kv, path_decals);
		
		if (!KvGotoFirstSubKey(kv)) {
			
			LogMessage("CFG File not found: %s", file);
			CloseHandle(kv);
			return false;
		}
		do {
			
			KvGetSectionName(kv, buffer, sizeof(buffer));
			PushArrayString(adt_decal_names, buffer);
			KvGetString(kv, "path", buffer, sizeof(buffer));
			PushArrayString(adt_decal_paths, buffer);
			int precacheId = PrecacheDecal(buffer, true);
			PushArrayCell(adt_decal_precache, precacheId);
			char decalpath[PLATFORM_MAX_PATH];
			Format(decalpath, sizeof(decalpath), buffer);
			Format(download, sizeof(download), "materials/%s.vmt", buffer);
			AddFileToDownloadsTable(download);
			vtf = CreateKeyValues("LightmappedGeneric");
			FileToKeyValues(vtf, download);
			KvGetString(vtf, "$basetexture", buffer, sizeof(buffer), buffer);
			CloseHandle(vtf);
			Format(download, sizeof(download), "materials/%s.vtf", buffer);
			AddFileToDownloadsTable(download);
		} while (KvGotoNextKey(kv));
		CloseHandle(kv);
	}

	kv = CreateKeyValues("Positions");
	FileToKeyValues(kv, path_mapdecals);
	
	if (!KvGotoFirstSubKey(kv)) {
		
		if (mode == READ) {
			LogMessage("CFG File for Map %s not found", mapName);
		}
		else {
			ReplyToCommand(client, "cfg_file_not_found", COLOR_DEFAULT, COLOR_GREEN, COLOR_DEFAULT, COLOR_GREEN, mapName, COLOR_DEFAULT);
		}
		
		CloseHandle(kv);
		return false;
	}
	do {
		KvGetSectionName(kv, buffer, sizeof(buffer));
		int id = FindStringInArray(adt_decal_names, buffer);
		if (id != -1) {
			
			if (mode == LIST) {
				ReplyToCommand(client, "list_decal", COLOR_DEFAULT, COLOR_GREEN, buffer);
			}
			
			float position[3];
			char strpos[8];
			int n = 1;
			Format(strpos, sizeof(strpos), "pos%d", n);
			KvGetVector(kv, strpos, position);
			while (position[0] != 0 && position[1] != 0 && position[2] != 0) {
				
				if (mode == READ) {
					PushArrayCell(adt_decal_id, id);
					PushArrayArray(adt_decal_position, view_as<int>(position));
				}
				else {
					ReplyToCommand(client, "list_decal_id", COLOR_DEFAULT, COLOR_GREEN, n);
					int DecalPos = GetConVarInt(md_pos);
					if (DecalPos)
						ReplyToCommand(client, "decal_position", COLOR_DEFAULT, COLOR_GREEN, position[0], position[1], position[2]);
				}
				n++;
				Format(strpos, sizeof(strpos), "pos%d", n);
				KvGetVector(kv, strpos, position);
			}
		}
	} while (KvGotoNextKey(kv));
	CloseHandle(kv);
	return true;
}

void TE_SetupBSPDecal(const float vecOrigin[3], int entity, int index) {
	
	TE_Start("BSP Decal");
	TE_WriteVector("m_vecOrigin", vecOrigin);
	TE_WriteNum("m_nEntity", entity);
	TE_WriteNum("m_nIndex", index);
}
