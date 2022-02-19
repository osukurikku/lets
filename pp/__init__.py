from common.constants import gameModes

from pp import ez, ez_peace

PP_CALCULATORS = {
    gameModes.STD: ez_peace.EzPeace,
    gameModes.TAIKO: ez_peace.EzPeace,
    gameModes.CTB: ez_peace.EzPeace,
    gameModes.MANIA: ez_peace.EzPeace,
}

PP_RELAX_CALCULATORS = {gameModes.STD: ez.Ez}
