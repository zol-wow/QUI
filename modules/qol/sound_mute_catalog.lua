local ADDON_NAME, ns = ...

ns.SoundMuteCatalog = {
    categories = {
        {
            key = "class", label = ns.L["Class"], entries = {
                { key = "class_warlock_imp",          label = ns.L["Warlock: Summon Imp"],       ids = { 551168 } },
                { key = "class_warlock_felguard",     label = ns.L["Warlock: Summon Felguard"],  ids = { 547320, 547328, 547335, 547332 } },
                { key = "class_warlock_succubus",     label = ns.L["Warlock: Summon Sayaad"],    ids = { 561163, 561168, 561157, 561154 } },
                { key = "class_warlock_succubus_slap", label = ns.L["Warlock: Sayaad slap"],      ids = { 561144, 1466150 } },
                { key = "class_warlock_summon",       label = ns.L["Warlock: Summon (generic)"], ids = { 2068351, 2068352 } },
                { key = "class_tcg_jackpot",          label = ns.L["Trading card 'Jackpot!' effect"], ids = { 6421997, 6421999, 6422001, 6422003, 6422005 } },
            },
        },
        {
            key = "dungeon", label = ns.L["Dungeons"], entries = {
                { key = "dungeon_xalatath",           label = ns.L["Xal'atath whispers"], ids = {
                    2530794, 2530811, 2530835, 5770084, 5770087, 5834619, 5834623, 5834632, 5835195, 5835211,
                    5835212, 5835214, 5835215, 5835725, 5835726, 5835729, 5854705, 5854706, 6178494, 6178497,
                    6178498, 6178500, 6178502, 6178504, 6178506, 6178508,
                } },
                { key = "dungeon_rookery_vokmar",     label = ns.L["The Rookery: Stormrider Vokmar"], ids = {
                    5858404, 5858470, 5858471, 5858472, 5858473, 5858474, 5858478, 5858481, 5858482, 5858485,
                } },
                { key = "dungeon_priory_etna",        label = ns.L["Priory of the Sacred Flame: Sister Etna Blayze"], ids = {
                    5839837, 5839839, 5839840, 5839841, 5839846, 5839847, 5839853, 5839854, 5839855, 5839860, 5839861,
                } },
                { key = "dungeon_cinderbrew",         label = ns.L["Cinderbrew Meadery: NPC chatter"], ids = {
                    5769388, 5769390, 5769391, 5769395, 5769396, 5769397, 5769400, 5779635, 5858873, 5858874,
                    5858875, 5858882, 5858888, 5858889, 5858890, 5858891, 5858892, 5858893, 5858894, 5858895,
                    5858896, 5858897, 5858898,
                } },
                { key = "dungeon_murderrow_belath",   label = ns.L["Murder Row: Belath Dawnblade"], ids = {
                    7238841, 7238805, 7238845, 1407468, 7238808, 1407465, 1407466, 1407463, 1406999, 1407010,
                    1407462, 7236595, 7236676, 7236705, 1401438, 1406995, 1407009, 1407464, 1281203, 1281205,
                    7236564, 7236621, 7236735, 7238811, 7238844, 7238846, 7238853, 1406998, 1407029, 1407031,
                    1407460, 1407461, 1407467, 1281201,
                } },
                { key = "dungeon_windrunner_lirath",  label = ns.L["Windrunner Spire: Lirath Windrunner"], ids = {
                    7236598, 7236624, 7238319, 7238330, 7238316, 7238318, 7238325, 7236569, 7236683, 7236712,
                    7236742, 7238309, 7238310, 7238311, 7238312, 7238313, 7238314, 7238315, 7238317, 7238320,
                    7238321, 7238322, 7238323, 7238324, 7238326, 7238327, 7238328, 7238329,
                } },
                { key = "dungeon_nalorakk_zuljarra",  label = ns.L["Den of Nalorakk: Zul'Jarra"], ids = {
                    7271224, 7271225, 7271226, 7271227, 7271228, 7271229, 7271230, 7271231, 7271250, 7271251,
                    7271252, 7271253, 7271254, 7271255, 7271256, 7271257, 7271232, 7271233, 7271234, 7271235,
                    7271236, 7271237, 7271238, 7271239, 7271242, 7271243, 7271244, 7271245, 7271246, 7271247,
                    7271248, 7271249, 7271240, 7271241,
                } },
                { key = "dungeon_mechagon",           label = ns.L["Operation: Mechagon NPCs"], ids = {
                    2931350, 2931351, 2931352, 2931353, 2931356, 2931435, 2931438, 2931439, 2931441, 2931354,
                    2931355, 2925336, 2925337, 2925338, 2925339, 2925340, 2925341, 2925342, 2925343, 2925345,
                    2925346, 2925347, 2925348, 2925351, 2925352, 2925353, 2925354, 2925355, 2925356, 2925357,
                    2925358, 2925359, 2925360,
                } },
                { key = "dungeon_stonevault",         label = ns.L["The Stonevault: encounter lines"], ids = { 5835282, 5835283, 5835268 } },
                { key = "dungeon_extra_set",          label = ns.L["Extra dungeon voice lines"], ids = { 7251817, 7251820, 7251823 } },
                { key = "dungeon_valeera",            label = ns.L["Valeera Sanguinar voice lines"], ids = {
                    7430043, 7430047, 7430050, 7430053, 7430056, 7430059, 7430063, 7430066, 7430069, 7430072,
                    7430075, 7430078, 7430082, 7430086, 7430089, 7430092, 7430095, 7430098, 7430101, 7430104,
                    7430107, 7430110, 7430113, 7430116, 7430119, 7430122, 7430125, 7430156, 7430159, 7430162,
                    7430165, 7430168, 7430171, 7430174, 7430177, 7430180, 7430183, 7430186, 7430189,
                } },
            },
        },
        {
            key = "mounts", label = ns.L["Mounts"], entries = {
                { key = "mount_pterodactyl",   label = ns.L["Pterrordax / pterodactyl screech"], ids = {
                    838877, 838879, 838881, 838883, 838885, 838887, 838903, 838905, 838907, 838909,
                    838911, 838913, 838915, 838917, 838919, 838921,
                } },
                { key = "mount_banlu",         label = ns.L["Ban-Lu (mount) chatter"], ids = {
                    1593212, 1593213, 1593214, 1593215, 1593216, 1593217, 1593218, 1593219, 1593220, 1593221,
                    1593222, 1593223, 1593224, 1593225, 1593226, 1593227, 1593228, 1593229, 1593230, 1593231,
                    1593232, 1593233, 1593234, 1593235, 1593236,
                } },
                { key = "mount_expedition_yak", label = ns.L["Grand Expedition Yak vendors"], ids = {
                    640336, 640338, 640340, 640314, 640316, 640318, 640320, 640180, 640182, 640184,
                    640158, 640160, 640162, 640164,
                } },
                { key = "mount_peafowl",       label = ns.L["Peafowl mount calls"], ids = { 5546937, 5546939, 5546941, 5546943 } },
                { key = "mount_wonderwing",    label = ns.L["Wonderwing 2.0"], ids = { 2148660, 2148661, 2148662, 2148663, 2148664 } },
                { key = "mount_chopper",       label = ns.L["Chopper / motorcycle engine"], ids = {
                    569859, 569858, 569855, 569857, 569863, 569856, 569860, 569862, 569861, 569854,
                    569845, 569852, 598736, 598745, 598748, 568252,
                } },
                { key = "mount_mimiron_head",  label = ns.L["Mimiron's Head"], ids = { 555364, 595097, 595100, 595103 } },
                { key = "mount_dreadwake",     label = ns.L["The Dreadwake (horn / bell / splash)"], ids = {
                    566064, 1838477, 2066773, 2066774, 2066775, 2066776, 2066777, 2066768, 2066769, 2066770,
                    2066771, 2066772,
                } },
                { key = "mount_storm_gryphon", label = ns.L["Storm gryphon (mount / thunder)"], ids = {
                    5356559, 5356561, 5356563, 5356565, 5356567, 5356569, 5356571, 3088094, 5357752, 5357769,
                    5357771, 5357773, 5357775,
                } },
                { key = "mount_g99_breakneck", label = ns.L["G-99 Breakneck (engine / drift)"], ids = {
                    2431461, 2431464, 2431465, 1487173, 1487174, 1487175, 1487176, 1487177, 1487178, 1487179,
                    1487180, 1487181, 1487182, 1659508, 1659509, 1659510, 1659511, 2138705, 6254769, 6382128,
                    6382130, 6382181, 6382183, 6382185, 6382187, 6382189, 6382191, 6382193, 6654849, 6654851,
                    6654853, 6654855, 6654857, 6654859, 6654861, 6654863, 6654865, 6654867,
                } },
            },
        },
        {
            key = "spells", label = ns.L["Spells"], entries = {
                { key = "spell_bloodlust", label = ns.L["Bloodlust / Heroism / Time Warp"], ids = {
                    568812, 569013, 569578, 569379, 568818, 569126, 568451, 4567038, 4567040, 4567042,
                    1416760, 1416761, 1416762, 4558551, 4558553, 4558555, 4558557, 4558559, 4575217, 4575219, 4575221,
                } },
            },
        },
        {
            key = "trinkets", label = ns.L["Trinkets"], entries = {
                { key = "trinket_gaze_alnseer", label = ns.L["Gaze of the Alnseer (trinket)"], ids = { 2144789, 2144790, 2144791 } },
            },
        },
        {
            key = "emotes", label = ns.L["Emotes"], entries = {
                { key = "emote_train", label = ns.L["/train emote (all races)"], ids = {
                    541239, 541157, 542600, 542526, 542896, 542818, 543093, 543085, 539203, 539219,
                    1306531, 1313588, 542017, 541769, 1732405, 1732030, 1730908, 1730534, 1951458, 1951457,
                    1903522, 1903049, 3106717, 3106252, 630296, 630298, 636621, 4737561, 4738601, 4741007,
                    4739531, 6021052, 6021067, 540734, 540535, 539881, 539802, 540947, 540870, 1304872,
                    1316209, 540275, 540271, 539730, 539516, 541601, 542206, 541463, 542035, 1733163,
                    1732785, 1731656, 1731282, 1902543, 1902030, 2491898, 2531204, 3107182, 3107651,
                } },
            },
        },
        {
            key = "professions", label = ns.L["Professions"], entries = {
                { key = "prof_skinning",   label = ns.L["Skinning"],   ids = { 567454, 567494, 567417 } },
                { key = "prof_herbalism",  label = ns.L["Herbalism (gathering)"], ids = { 569824, 569825, 569797, 569818 } },
                { key = "prof_mining",     label = ns.L["Mining"],     ids = { 569801, 569811, 569792, 569794, 569821 } },
                { key = "prof_alchemy",    label = ns.L["Alchemy (flask / potion)"], ids = { 569793, 569802, 569812 } },
            },
        },
        {
            key = "interface", label = ns.L["Interface & UI"], entries = {
                { key = "iface_bnet_toast",      label = ns.L["Battle.net notification toast"], ids = { 567402 } },
                { key = "iface_change_tab",      label = ns.L["UI tab change click"], ids = { 567422, 567507, 567433 } },
                { key = "iface_enter_queue",     label = ns.L["Enter LFG queue"], ids = { 568587 } },
                { key = "iface_readycheck",      label = ns.L["Ready check"], ids = { 567478 } },
                { key = "iface_raid_warning",    label = ns.L["Raid warning"], ids = { 567397 } },
                { key = "iface_coin",            label = ns.L["Coin / gold sound"], ids = { 567428 } },
                { key = "iface_mailbox_open",    label = ns.L["Open mailbox"], ids = { 567440 } },
                { key = "iface_summoning_stone", label = ns.L["Summoning stone portal"], ids = { 568938, 1684459, 1684460, 1684461, 1684462, 1684463 } },
                { key = "iface_whisper",         label = ns.L["Incoming whisper"], ids = { 567421 } },
                { key = "iface_ping_minimap",    label = ns.L["Ping: minimap"], ids = { 567416 } },
                { key = "iface_ping_warning",    label = ns.L["Ping: warning"], ids = { 5342387 } },
                { key = "iface_ping_generic",    label = ns.L["Ping: generic"], ids = { 5339002 } },
                { key = "iface_ping_assist",     label = ns.L["Ping: assist"], ids = { 5339006 } },
                { key = "iface_ping_omw",        label = ns.L["Ping: on my way"], ids = { 5340605 } },
                { key = "iface_ping_attack",     label = ns.L["Ping: attack"], ids = { 5350036 } },
                { key = "iface_quest_complete",  label = ns.L["Quest complete"], ids = { 567439 } },
                { key = "iface_ah_open",         label = ns.L["Auction house open"], ids = { 567482 } },
                { key = "iface_ah_close",        label = ns.L["Auction house close"], ids = { 567499 } },
            },
        },
        {
            key = "misc", label = ns.L["Miscellaneous"], entries = {
                { key = "misc_eating", label = ns.L["Eating / drinking"], ids = { 567612 } },
            },
        },
    },
}
