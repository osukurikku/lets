from common.constants import gameModes

from pp import ez, ez_rosu_pp

PP_CALCULATORS = {
    gameModes.STD: ez_rosu_pp.EzRosu,
    gameModes.TAIKO: ez_rosu_pp.EzRosu,
    gameModes.CTB: ez_rosu_pp.EzRosu,
    gameModes.MANIA: ez_rosu_pp.EzRosu
}

PP_RELAX_CALCULATORS = {
    gameModes.STD: ez.Ez
}
