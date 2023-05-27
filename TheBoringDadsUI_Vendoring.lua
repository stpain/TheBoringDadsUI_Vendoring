local name, addon = ...;

Mixin(addon, CallbackRegistryMixin)
addon:GenerateCallbackEvents({
    "Bags_Updated",
    "Item_OnVendorFlagChanged",
})
CallbackRegistryMixin.OnLoad(addon);

TheBoringDadsUI_VendoringMixin = {
    type = "frame",
    name = "Vendoring",
    icon = 133785,
    selectedCharacter = "",
    vendorItems = {},
};

function TheBoringDadsUI_VendoringMixin:OnLoad()
    self:RegisterEvent("BAG_UPDATE_DELAYED")
    self:RegisterEvent("PLAYER_ENTERING_WORLD")

    self.autoJunk.label:SetText("Auto Vendor Junk")

    addon:RegisterCallback("Item_OnVendorFlagChanged", self.Item_OnVendorFlagChanged, self)

    self.vendorItems:SetScript("OnClick", function()
        if #self.vendorItems > 0 then
            local i = #self.vendorItems;
            local vendorTicker = C_Timer.NewTicker(0.075, function()
                local item = self.vendorItems[i]
                if item then
                    C_Item.UnlockItemByGUID(item.guid)
                    C_Container.UseContainerItem(item.bagId, item.slotId)
                    print(string.format("Sold %s", item.link))
                end
                table.remove(self.vendorItems, i)
                i = i - 1;
                addon:TriggerEvent("Item_OnVendorFlagChanged", nil, nil)

            end, #self.vendorItems)
        end
    end)
end

function TheBoringDadsUI_VendoringMixin:OnEvent(event, ...)
    if self[event] then
        self[event](self, ...)
    end
end

function TheBoringDadsUI_VendoringMixin:PLAYER_ENTERING_WORLD(initial, reload)
    
    if not TBD_DB_VENDORING then
        TBD_DB_VENDORING = {
            characters = {},
        }
    end
    self.db = TBD_DB_VENDORING

    local name, realm = UnitFullName("player")
    if not realm then
        realm = GetNormalizedRealmName()
    end
    self.currentCharacter = string.format("%s-%s", name, realm)

    if not self.db.characters[self.currentCharacter] then
        self.db.characters[self.currentCharacter] = {};
    end

    TheBoringDad:RegisterModule(self)

    self:UnregisterEvent("PLAYER_ENTERING_WORLD")
end


function TheBoringDadsUI_VendoringMixin:LoadCharacters()
    if self.db and self.db.characters then
        for nameRealm, _ in pairs(self.db.characters) do
            self.charactersListview.DataProvider:Insert({
                label = nameRealm,
                onMouseDown = function()
                    self.selectedCharacter = nameRealm;
                end,
            })
        end
    end
end

function TheBoringDadsUI_VendoringMixin:Item_OnVendorFlagChanged(item, flag)

    if type(item) == "table" then
        if flag == true then
            table.insert(self.vendorItems, item)
            C_Item.LockItemByGUID(item.guid)
        else
            local key;
            for k, _item in ipairs(self.vendorItems) do
                if (_item.link == item.link) and (_item.bagId == item.bagId) and (_item.slotId == item.slotId) then
                    key = k;
                end
            end
            if key then
                table.remove(self.vendorItems, key)
                C_Item.UnlockItemByGUID(item.guid)
            end
        end
    end

    self.info:SetText(string.format("%d items selected", #self.vendorItems))
end


function TheBoringDadsUI_VendoringMixin:BAG_UPDATE_DELAYED()
    
    local items = {}
    local classInfo = {}

    for bag = 0, 4 do
        
        for slot = 1, C_Container.GetContainerNumSlots(bag) do

            local info = C_Container.GetContainerItemInfo(bag, slot)
            if info and info.itemID then
                local itemLoc = ItemLocation:CreateFromBagAndSlot(bag, slot)
                local item = Item:CreateFromItemLocation(itemLoc)
                local itemGUID = item:GetItemGUID()
                local itemName, itemLink, itemQuality, itemLevel, itemMinLevel, itemType, itemSubType, itemStackCount, itemEquipLoc, itemTexture, sellPrice, classID, subclassID, bindType, expacID, setID, isCraftingReagent = GetItemInfo(info.itemID)
                table.insert(items, {
                    link = info.hyperlink,
                    count = info.stackCount,
                    icon = info.iconFileID,
                    itemId = info.itemID,
                    bagId = bag,
                    slotId = slot,
                    quality = itemQuality or 0,
                    classId = classID,
                    subClassId = subclassID,
                    sellPrice = sellPrice or 0,
                    guid = itemGUID,
                })

                if not classInfo[classID] then
                    classInfo[classID] = {
                        numItems = info.stackCount,
                        value = info.stackCount * (sellPrice or 0);
                        slotsUsed = 1,
                    }
                else
                    classInfo[classID].numItems = classInfo[classID].numItems + info.stackCount;
                    classInfo[classID].value = classInfo[classID].value + (info.stackCount * sellPrice);
                    classInfo[classID].slotsUsed = classInfo[classID].slotsUsed + 1
                end
            end
            
        end
    end

    table.sort(items, function(a, b)
        if a.classId == b.classId then
            if a.subClassId == b.subClassId then
                if a.quality == b.quality then
                    return a.link < b.link
                else
                    return a.quality < b.quality
                end
            else
                return a.subClassId < b.subClassId
            end
        else
            return a.classId < b.classId
        end
    end)

    self.db.characters[self.currentCharacter].items = items;

    self.itemsListview.DataProvider:Flush()

    local classIdHeaders = {}
    for k, item in ipairs(items) do
        if not classIdHeaders[item.classId] then
            self.itemsListview.DataProvider:Insert({
                isHeader = true,
                header = GetItemClassInfo(item.classId),
                info = classInfo[item.classId],
            })
            classIdHeaders[item.classId] = true
        end
        self.itemsListview.DataProvider:Insert(item)
    end

end




TheBoringDadsUI_VendoringListviewItemMixin = {}
function TheBoringDadsUI_VendoringListviewItemMixin:OnLoad()
    self:SetScript("OnLeave", function()
        GameTooltip_SetDefaultAnchor(GameTooltip, UIParent)
    end)
end

function TheBoringDadsUI_VendoringListviewItemMixin:SetDataBinding(binding, height)

    self.header:Hide()
    self.info:Hide()
    self.checkbox:Hide()

    if binding.isHeader then
        self.header:SetText(binding.header)
        self.header:Show()
        self.info:SetText(string.format("%d items %d slots %s", binding.info.numItems, binding.info.slotsUsed, GetCoinTextureString(binding.info.value)))
        self.info:Show()
        self.background:Show()
        self:EnableMouse(false)    
    else
        self.item = binding;
        self:EnableMouse(true)
        self.background:Hide()
        self.checkbox.label:SetText(binding.link)
        self.checkbox:Show()
        self.checkbox:SetScript("OnClick", function()
            if self.item then
                addon:TriggerEvent("Item_OnVendorFlagChanged", self.item, self.checkbox:GetChecked())
            end
        end)
        self.info:SetText(string.format("%s [Bag %d Slot %d]", GetItemSubClassInfo(binding.classId, binding.subClassId), binding.bagId, binding.slotId))
        self.info:Show()
    end


end


function TheBoringDadsUI_VendoringListviewItemMixin:OnEnter()
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:SetHyperlink(self.item.link)
    GameTooltip:Show()
end

function TheBoringDadsUI_VendoringListviewItemMixin:ResetDataBinding()
    self.checkbox:SetChecked(false)
    self.checkbox:SetScript("OnClick", nil)
end