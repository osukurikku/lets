from common.constants import gameModes
from pp import rippoppai
from pp import semyonppc
from pp import cicciobello

PP_CALCULATORS = {
    gameModes.STD: rippoppai.oppai,
    gameModes.TAIKO: rippoppai.oppai,
    gameModes.CTB: cicciobello.Cicciobello,
    gameModes.MANIA: semyonppc.Omppc
}