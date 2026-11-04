local addonName, WSGS = ...
LibStub("AceAddon-3.0"):NewAddon(WSGS, addonName, "AceConsole-3.0", "AceEvent-3.0")
WSGS.Private = {
    Character = {}, Equipment = {}, Enhancements = {}, EquipmentSets = {},
    Builds = {}, Shopping = {}, Views = {}, Diagnostics = {}
}

WSGS.Builds = {}
WSGS.Character = {}
WSGS.Equipment = {}
WSGS.Enhancements = {}
WSGS.EquipmentSets = {}
WSGS.Views = {}
