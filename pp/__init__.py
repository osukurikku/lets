from common.constants import gameModes
from pp import osuperfomance

from pp import ez

PP_CALCULATORS = {
    gameModes.STD: ez.Ez,
    gameModes.TAIKO: osuperfomance.OsuPerfomanceCalculation,
    gameModes.CTB: osuperfomance.OsuPerfomanceCalculation,
    gameModes.MANIA: osuperfomance.OsuPerfomanceCalculation
}

PP_RELAX_CALCULATORS = {
    gameModes.STD: ez.Ez
}