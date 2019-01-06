from common.constants import gameModes
from pp import rippoppai
from pp import relaxoppai
from pp import wifipiano2
from pp import cicciobello

PP_CALCULATORS = {
    gameModes.STD: rippoppai.oppai,
    gameModes.TAIKO: rippoppai.oppai,
    gameModes.CTB: cicciobello.Cicciobello,
    gameModes.MANIA: wifipiano2.piano
}

PP_RELAX_CALCULATORS = {
    gameModes.STD: relaxoppai.oppai,
    gameModes.TAIKO: relaxoppai.oppai
}