#include <clientprefs>

#undef REQUIRE_PLUGIN
#include <shop>
#include <vip_core>

Menu hMainMenu;

int iMode;

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

#define CheckVIPAccess(%1,%2)		(Shop_IsClientHasItem(%1, skyboxList[%2].shopId))
#define CheckSHOPAccess(%1,%2)		(StrContains(skyboxList[iSkyboxIndex].sAccessGroups, Players[iClient].sVipGroup, false) != -1)

Cookie hSelectCookie;
CategoryId iShopCategory;

ConVar hSkybox;

enum struct Player
{
	int iSelectedSkybox;
	int iLoadingState;
	
	char sVipGroup[64];
}

Player Players[MAXPLAYERS + 1];

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	if (late)
	{
		if (LibraryExists("shop"))
			iMode |= LOAD_SHOP;
		if (LibraryExists("vip_core"))
			iMode |= LOAD_VIP;
	}
	
	return APLRes_Success;
}

public void Shop_Started()
{
	iShopCategory = Shop_RegisterCategory("skybox", "Скайбоксы", "Скайбоксы", OnShopDisplay)
}

public bool OnShopDisplay(int iClient, CategoryId category_id, const char[] category, const char[] name, char[] buffer, int maxlen, ShopMenu menu)
{
	OpenSkyBoxesMenu(iClient);
	return false;
}

public void OnPluginStart()
{
	hSkybox = FindConVar("sv_skyname");
	hSelectCookie = new Cookie("skybox_selected", "", CookieAccess_Private);
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
	Players[iClient].iSelectedSkybox = -1;
	char sClientSkybox[64];
	hSelectCookie.Get(iClient, sClientSkybox, sizeof sClientSkybox);
	for (int i = 0; i < skyboxCount; i++)
	{
		if (!strcmp(skyboxList[i].sName, sClientSkybox, false))
		{
			Players[iClient].iSelectedSkybox = i;
			break;
		}
	}
	
	CheckLoadingState(iClient);
}

void CheckLoadingState(int iClient)
{
	if (VIP_Loaded() && !VIP_ClientLoaded(iClient))return;
	if (SHOP_Loaded() && !SHOP_ClientLoaded(iClient))return;
	if (!COOKIES_ClientLoaded(iClient))return;
	
	if (!CheckSkyboxAccess(iClient, Players[iClient].iSelectedSkybox))Players[iClient].iSelectedSkybox = -1;
}

bool CheckSkyboxAccess(int iClient, int iSkyboxIndex)
{
	if (iSkyboxIndex == -1)return true;
	if (SHOP_Loaded() && CheckSHOPAccess(iClient, iSkyboxIndex))return true;
	if (VIP_Loaded() && CheckVIPAccess(iClient, iSkyboxIndex))return true;
	
	return false;
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
			Shop_SetItemPrice(iShopCost);
			Shop_SetCallbacks(OnItemRegistered, OnItemToggled);
			Shop_EndItem();
		}
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
	
	if (isOn)
	{
		SetSkybox(iClient, iSkybox);
	} else
	{
		DisableSkybox(iClient);
	}
}

void OpenSkyBoxesMenu(iClient)
{
	Menu hMenu = new Menu(MainMenuHandler);
	hMenu.SetTitle("  Скайбоксы");
	
	for (int i = 0; i < skyboxCount; i++)
	{
		hMenu.AddItem(NULL_STRING, skyboxList[i].sDisplayName, (!IsSHOPSkybox(i) && IsVIPSkybox(i) && !CheckVIPAccess(iClient, i)) ? ITEMDRAW_DISABLED:ITEMDRAW_DEFAULT);
	}
	
	hMenu.Display(iClient, 0);
}

public int MainMenuHandler(Menu menu, MenuAction action, int iClient, int iSkybox)
{
	switch (action)
	{
		case MenuAction_Select:
		{
			if (IsVIPSkybox(iSkybox))
			{
				if (CheckVIPAccess(iClient, iSkybox))
				{
					Players[iClient].iSelectedSkybox = iSkybox;
					SetSkybox(iClient, iSkybox);
					
				} else
					if (!IsSHOPSkybox(iSkybox))
				{
					PrintToChat(iClient, " \x07У вас нет доступа");
					return 0;
				}
			}
			
			Shop_ShowItemPanel(iClient, skyboxList[iSkybox].shopId);
		}
		case MenuAction_End:
		{
			delete menu;
		}
	}
}


public void OnPluginEnd()
{
	if (SHOP_Loaded())Shop_UnregisterMe();
}

void SetSkybox(int iClient, int iSkybox)
{
	hSkybox.ReplicateToClient(iClient, skyboxList[iSkybox].sName);
}

void DisableSkybox(int iClient)
{
	char sBuffer[64];
	hSkybox.GetString(sBuffer, sizeof sBuffer);
	
	hSkybox.ReplicateToClient(iClient, sBuffer);
} 