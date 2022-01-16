#include <clientprefs>
#include <sdktools>

#undef REQUIRE_PLUGIN
#include <shop>
#include <vip_core>

int m_skybox3dAreaOffs;
int m_hObserverTargetOffs;
int m_iObserverModeOffs;

char sDefaultSkybox[64];

enum
{
	LOAD_SHOP = (1 << 0), 
	LOAD_VIP = (1 << 1), 
	LOAD_COOKIES = (1 << 2)
}

enum struct Skybox
{
	char sName[64];
	char sDisplayName[64];
	
	int iMode;
	
	ItemId shopId;
	
	int iShopCost;
	int iShopDuration;
	char sAccessGroups[512];
}

Skybox skyboxList[64];
int skyboxCount;

#define VIP_Loaded() 				(iMode & LOAD_VIP)
#define SHOP_Loaded() 				(iMode & LOAD_SHOP)

#define VIP_ClientLoaded(%1) 		(Players[%1].iLoadingState & LOAD_VIP)
#define SHOP_ClientLoaded(%1) 		(Players[%1].iLoadingState & LOAD_SHOP)
#define COOKIES_ClientLoaded(%1)	(Players[%1].iLoadingState & LOAD_COOKIES)

#define IsVIPSkybox(%1)				(skyboxList[%1].iMode & LOAD_VIP)
#define IsSHOPSkybox(%1) 			(skyboxList[%1].iMode & LOAD_SHOP)

#define CheckSHOPAccess(%1,%2)		(Shop_IsClientHasItem(%1, skyboxList[%2].shopId))
#define CheckVIPAccess(%1,%2)		(Players[%1].sVipGroup[0] && StrContains(skyboxList[%2].sAccessGroups, Players[%1].sVipGroup, false) != -1)

Cookie hSelectCookie;
CategoryId iShopCategory;
ConVar hSkybox;
int iMode;

#define VIP_FEATURE "skybox"

enum struct Player
{
	int iSelectedSkybox;
	int iLoadingState;
	
	int iActiveSkybox;
	int iMenuSkybox;
	char sVipGroup[64];
}

Player Players[MAXPLAYERS + 1];

bool bLate;
public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	bLate = late;
	return APLRes_Success;
}

public void Shop_Started()
{
	iShopCategory = Shop_RegisterCategory("skybox", "Скайбоксы", "Небо", .cat_select = OnShopSelect);
	LoadConfig();
}

public void VIP_OnVIPLoaded()
{
	VIP_IsValidFeature(VIP_FEATURE) && VIP_UnregisterFeature(VIP_FEATURE);
	VIP_RegisterFeature(VIP_FEATURE, _, SELECTABLE, OnSelectVIPFeature);
}

public bool OnSelectVIPFeature(int iClient, const char[] szFeature)
{
	OpenSkyBoxesMenu(iClient);
	return false;
}

public bool OnShopSelect(int iClient, CategoryId category_id, const char[] category, ShopMenu menu)
{
	OpenSkyBoxesMenu(iClient);
	return false;
}

public void OnPluginStart()
{
	m_skybox3dAreaOffs = FindSendPropInfo("CBasePlayer", "m_skybox3d.area");
	m_hObserverTargetOffs = FindSendPropInfo("CBasePlayer", "m_hObserverTarget");
	m_iObserverModeOffs = FindSendPropInfo("CBasePlayer", "m_iObserverMode");
	
	hSkybox = FindConVar("sv_skyname");
	hSkybox.AddChangeHook(OnSkyboxChanged);
	hSkybox.GetString(sDefaultSkybox, sizeof sDefaultSkybox);
	hSelectCookie = new Cookie("skybox_selected", "", CookieAccess_Private);
	
	if (bLate)
	{
		if (LibraryExists("shop"))
		{
			iMode |= LOAD_SHOP;
			
			if (Shop_IsStarted())Shop_Started();
		} else LoadConfig();
		if (LibraryExists("vip_core"))
		{
			iMode |= LOAD_VIP;
			
			if (VIP_IsVIPLoaded())VIP_OnVIPLoaded();
		}
		
		for (int i = 1; i < MaxClients + 1; i++)
		{
			if (IsClientInGame(i) && !IsFakeClient(i))
			{
				OnClientConnected(i);
				
				if (AreClientCookiesCached(i))OnClientCookiesCached(i);
				if (Shop_IsAuthorized(i))Shop_OnAuthorized(i);
				VIP_CheckClient(i);
				
			}
		}
	}
	
	RegConsoleCmd("sm_skybox", CMD_Skybox);
}

public Action CMD_Skybox(int iClient, int iArgs)
{
	OpenSkyBoxesMenu(iClient);
	return Plugin_Handled;
}

public void OnSkyboxChanged(ConVar cvar, const char[] oldValue, const char[] newValue)
{
	strcopy(sDefaultSkybox, sizeof sDefaultSkybox, newValue)
}

public void OnLibraryAdded(const char[] lib)
{
	if (!strcmp(lib, "shop", false))
		iMode |= LOAD_SHOP;
	else if (!strcmp(lib, "vip_core", false))
		iMode |= LOAD_VIP;
}

public void OnLibraryRemoved(const char[] lib)
{
	if (!strcmp(lib, "shop", false))
		iMode &= ~LOAD_SHOP;
	else if (!strcmp(lib, "vip_core", false))
		iMode &= ~LOAD_VIP;
}

public void OnClientCookiesCached(int iClient)
{
	Players[iClient].iLoadingState |= LOAD_COOKIES;
	char sClientSkybox[64];
	hSelectCookie.Get(iClient, sClientSkybox, sizeof sClientSkybox);
	if (sClientSkybox[0])
	{
		for (int i = 0; i < skyboxCount; i++)
		{
			if (!strcmp(skyboxList[i].sName, sClientSkybox, false))
			{
				Players[iClient].iSelectedSkybox = i;
				break;
			}
		}
	}
	
	CheckLoadingState(iClient);
}

void CheckLoadingState(int iClient)
{
	if (VIP_Loaded() && !VIP_ClientLoaded(iClient))return;
	if (SHOP_Loaded() && !SHOP_ClientLoaded(iClient))return;
	if (!COOKIES_ClientLoaded(iClient))return;
	
	if (Players[iClient].iSelectedSkybox != -1)
	{
		if (!CheckSkyboxAccess(iClient, Players[iClient].iSelectedSkybox))Players[iClient].iSelectedSkybox = -1;
		else SetSkybox(iClient, Players[iClient].iSelectedSkybox);
	}
}

bool CheckSkyboxAccess(int iClient, int iSkyboxIndex)
{
	if (SHOP_Loaded() && CheckSHOPAccess(iClient, iSkyboxIndex))return true;
	if (VIP_Loaded() && CheckVIPAccess(iClient, iSkyboxIndex))return true;
	
	return false;
}

public void Shop_OnAuthorized(int iClient)
{
	Players[iClient].iLoadingState |= LOAD_SHOP;
	CheckLoadingState(iClient);
}

public void VIP_OnClientLoaded(int iClient, bool bIsVIP)
{
	Players[iClient].iLoadingState |= LOAD_VIP;
	if (bIsVIP)VIP_GetClientVIPGroup(iClient, Players[iClient].sVipGroup, sizeof Player::sVipGroup);
	CheckLoadingState(iClient);
}

public void VIP_OnVIPClientAdded(int iClient, int iAdmin)
{
	VIP_GetClientVIPGroup(iClient, Players[iClient].sVipGroup, sizeof Player::sVipGroup);
}

public void VIP_OnVIPClientRemoved(int iClient, const char[] szReason, int iAdmin)
{
	Players[iClient].sVipGroup[0] = '\0';
}

public void OnClientConnected(int iClient)
{
	Players[iClient].iLoadingState = 0;
	Players[iClient].iSelectedSkybox = -1;
	Players[iClient].iActiveSkybox = -1;
	Players[iClient].sVipGroup[0] = '\0';
}

void LoadConfig()
{
	char sPath[PLATFORM_MAX_PATH];
	KeyValues hKv = new KeyValues("skybox");
	BuildPath(Path_SM, sPath, sizeof sPath, "configs/skybox.ini");
	hKv.ImportFromFile(sPath);
	
	int iShopCost;
	
	hKv.GotoFirstSubKey();
	do
	{
		hKv.GetSectionName(skyboxList[skyboxCount].sName, sizeof Skybox::sName);
		hKv.GetString("display", skyboxList[skyboxCount].sDisplayName, sizeof Skybox::sDisplayName);
		iShopCost = hKv.GetNum("shop_cost", -1);
		if (iShopCost != -1)
		{
			skyboxList[skyboxCount].iShopCost = iShopCost;
			skyboxList[skyboxCount].iMode |= LOAD_SHOP;
			
			Shop_StartItem(iShopCategory, skyboxList[skyboxCount].sName);
			Shop_SetCallbacks(OnItemRegistered, OnItemToggled);
			Shop_SetInfo(skyboxList[skyboxCount].sDisplayName, "", iShopCost, -1, Item_Togglable, hKv.GetNum("shop_duration", 0));
			Shop_EndItem();
		} else skyboxList[skyboxCount].shopId = view_as<ItemId>(-1);
		hKv.GetString("vip_groups", skyboxList[skyboxCount].sAccessGroups, Skybox::sAccessGroups);
		if (skyboxList[skyboxCount].sAccessGroups[0])
		{
			skyboxList[skyboxCount].iMode |= LOAD_VIP;
		}
		skyboxCount++;
	} while (hKv.GotoNextKey());
}

public void OnItemRegistered(CategoryId category_id, const char[] category, const char[] item, ItemId item_id)
{
	for (int i = 0; i < skyboxCount; i++)
	{
		if (!strcmp(item, skyboxList[i].sName, false))
		{
			skyboxList[i].shopId = item_id;
			break;
		}
	}
}

public ShopAction OnItemToggled(int iClient, CategoryId category_id, const char[] category, ItemId item_id, const char[] item, bool isOn, bool elapsed)
{
	int iSkybox;
	for (; iSkybox < skyboxCount; iSkybox++)
	{
		if (item_id == skyboxList[iSkybox].shopId)break;
	}
	
	if (isOn || elapsed)
	{
		Players[iClient].iSelectedSkybox = -1;
		DisableSkybox(iClient);
		return Shop_UseOff;
	}
	
	ToggleShopSkyboxItem(iClient, Toggle_Off);
	Players[iClient].iSelectedSkybox = iSkybox;
	SetSkybox(iClient, iSkybox);
	SaveSkybox(iClient);
	return Shop_UseOn;
}

void ToggleShopSkyboxItem(int iClient, ToggleState toggle)
{
	int iCurrentSkybox = Players[iClient].iSelectedSkybox;
	if (iCurrentSkybox != -1 && skyboxList[iCurrentSkybox].shopId != view_as<ItemId>(-1))
	{
		Shop_ToggleClientItem(iClient, skyboxList[iCurrentSkybox].shopId, toggle);
	}
}

void OpenSkyBoxesMenu(iClient)
{
	Menu hMenu = new Menu(MainMenuHandler);
	hMenu.SetTitle("  Скайбоксы");
	
	char sTempDisplay[96];
	for (int i = 0; i < skyboxCount; i++)
	{
		if (i == Players[iClient].iSelectedSkybox)
		{
			Format(sTempDisplay, sizeof sTempDisplay, "%s ✓", skyboxList[i].sDisplayName);
			hMenu.AddItem(NULL_STRING, sTempDisplay);
		} else
			hMenu.AddItem(NULL_STRING, skyboxList[i].sDisplayName);
	}
	
	hMenu.Display(iClient, 0);
}

public int MainMenuHandler(Menu menu, MenuAction action, int iClient, int iItem)
{
	switch (action)
	{
		case MenuAction_Select:
		{
			Players[iClient].iMenuSkybox = iItem;
			OpenSkyBoxMenu(iClient);
		}
		case MenuAction_End:
		{
			delete menu;
		}
	}
	return 0;
}

void OpenSkyBoxMenu(int iClient)
{
	int iCurrentSkybox = Players[iClient].iMenuSkybox;
	Menu hMenu = new Menu(SkyboxMenuHandler);
	hMenu.SetTitle(skyboxList[iCurrentSkybox].sDisplayName);
	
	if (Players[iClient].iSelectedSkybox == iCurrentSkybox)
		hMenu.AddItem(NULL_STRING, "Выключить\n \n ");
	else
	{
		if ((IsVIPSkybox(iCurrentSkybox) && CheckVIPAccess(iClient, iCurrentSkybox)) || (IsSHOPSkybox(iCurrentSkybox) && CheckSHOPAccess(iClient, iCurrentSkybox)))
		{
			hMenu.AddItem(NULL_STRING, "Включить\n \n ");
		} else
		{
			hMenu.AddItem(NULL_STRING, "Включить\n \n ", ITEMDRAW_DISABLED);
		}
	}
	
	if (IsSHOPSkybox(iCurrentSkybox))
	{
		hMenu.AddItem(NULL_STRING, "Информация в магазине");
	}
	
	hMenu.ExitBackButton = true;
	
	hMenu.Display(iClient, 0);
}

public int SkyboxMenuHandler(Menu menu, MenuAction action, int iClient, int iItem)
{
	switch (action)
	{
		case MenuAction_Select:
		{
			int iSkybox = Players[iClient].iMenuSkybox;
			
			if (iItem == 1)
			{
				Shop_ShowItemPanel(iClient, skyboxList[iSkybox].shopId);
				return 0;
			}
			
			if (iSkybox == Players[iClient].iSelectedSkybox)
			{
				ToggleShopSkyboxItem(iClient, Toggle_Off);
				Players[iClient].iSelectedSkybox = -1;
				DisableSkybox(iClient);
				
				OpenSkyBoxMenu(iClient);
				return 0;
			}
			
			if (IsVIPSkybox(iSkybox) && CheckVIPAccess(iClient, iSkybox))
			{
				ToggleShopSkyboxItem(iClient, Toggle_Off);
				Players[iClient].iSelectedSkybox = iSkybox;
				ToggleShopSkyboxItem(iClient, Toggle_On);
				SetSkybox(iClient, iSkybox);
				SaveSkybox(iClient);
				OpenSkyBoxMenu(iClient);
				return 0;
			} else if (IsSHOPSkybox(iSkybox) && CheckSHOPAccess(iClient, iSkybox))
			{
				ToggleShopSkyboxItem(iClient, Toggle_Off);
				Players[iClient].iSelectedSkybox = iSkybox;
				ToggleShopSkyboxItem(iClient, Toggle_On);
				SetSkybox(iClient, iSkybox);
				SaveSkybox(iClient);
				OpenSkyBoxMenu(iClient);
				return 0;
			} else
			{
				PrintToChat(iClient, " \x07У вас нет доступа");
				OpenSkyBoxMenu(iClient)
				return 0;
			}
			
		}
		case MenuAction_End:
		{
			delete menu;
		}
		case MenuAction_Cancel:
		{
			if(iItem == MenuCancel_ExitBack)
				OpenSkyBoxesMenu(iClient);
		}
	}
	return 0;
}

public void OnPluginEnd()
{
	if (SHOP_Loaded())Shop_UnregisterMe();
	if (VIP_Loaded())VIP_UnregisterMe();
}

void SaveSkybox(int iClient)
{
	hSelectCookie.Set(iClient, skyboxList[Players[iClient].iSelectedSkybox].sName);
}

void SetSkybox(int iClient, int iSkybox)
{
	SetEntData(iClient, m_skybox3dAreaOffs, 255);
	hSkybox.ReplicateToClient(iClient, skyboxList[iSkybox].sName);
	Players[iClient].iActiveSkybox = iSkybox;
}

void DisableSkybox(int iClient)
{
	SetEntData(iClient, m_skybox3dAreaOffs, 0);
	hSkybox.ReplicateToClient(iClient, sDefaultSkybox);
	Players[iClient].iActiveSkybox = -1;
}

public void OnMapStart()
{
	for (int i = 0; i < skyboxCount; i++)
	{
		AddSkybox(skyboxList[i].sName);
	}
}

void AddSkybox(char[] sName)
{
	static char suffix[][] = {
		"bk", 
		"Bk", 
		"dn", 
		"Dn", 
		"ft", 
		"Ft", 
		"lf", 
		"Lf", 
		"rt", 
		"Rt", 
		"up", 
		"Up", 
	};
	static char sBuffer[PLATFORM_MAX_PATH];
	for (int i = 0; i < sizeof(suffix); ++i)
	{
		FormatEx(sBuffer, sizeof(sBuffer), "materials/skybox/%s%s.vtf", sName, suffix[i]);
		if (FileExists(sBuffer, false))AddFileToDownloadsTable(sBuffer);
		
		FormatEx(sBuffer, sizeof(sBuffer), "materials/skybox/%s%s.vmt", sName, suffix[i]);
		if (FileExists(sBuffer, false))AddFileToDownloadsTable(sBuffer);
	}
}

public void OnPlayerRunCmdPost(int iClient)
{
	if (IsFakeClient(iClient))return;
	
	static int iOldObsMode[MAXPLAYERS + 1];
	int iCurrentObsMode = GetEntData(iClient, m_iObserverModeOffs);
	if (iCurrentObsMode == 4)
	{
		int iCurrentTarget = GetEntDataEnt2(iClient, m_hObserverTargetOffs);
		if (iCurrentTarget < 1)return;
		
		int iTargetSkybox = Players[iCurrentTarget].iSelectedSkybox;
		if (Players[iClient].iActiveSkybox != iTargetSkybox)
		{
			if (iTargetSkybox == -1)DisableSkybox(iClient);
			else SetSkybox(iClient, iTargetSkybox);
		}
	} else
	{
		if (iOldObsMode[iClient] != 4)
		{
			int iCurrentSkybox = Players[iClient].iSelectedSkybox;
			if (iCurrentSkybox != Players[iClient].iActiveSkybox)
			{
				if (iCurrentSkybox == -1)DisableSkybox(iClient);
				else SetSkybox(iClient, iCurrentSkybox);
			}
			iOldObsMode[iClient] = iCurrentObsMode;
		}
	}
} 