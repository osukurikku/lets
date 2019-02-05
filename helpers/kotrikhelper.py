def zingonify(d):
    """
    Zingonifies a string

    :param d: input dict
    :return: zingonified dict as str
    """
    return "|".join(f"{k}:{v}" for k, v in d.items())

def parse_mods(mods):
    ScoreMods = ""
					
    if mods == 0:
        ScoreMods += "nomod"
    if mods & mods.NOFAIL > 0:
        ScoreMods += "NF"
    if mods & mods.EASY > 0:
        ScoreMods += "EZ"
    if mods & mods.HIDDEN > 0:
        ScoreMods += "HD"
    if mods & mods.HARDROCK > 0:
        ScoreMods += "HR"
    if mods & mods.DOUBLETIME > 0:
        ScoreMods += "DT"
    if mods & mods.HALFTIME > 0:
        ScoreMods += "HT"
    if mods & mods.FLASHLIGHT > 0:
        ScoreMods += "FL"
    if mods & mods.SPUNOUT > 0:
        ScoreMods += "SO"
    if mods & mods.TOUCHSCREEN > 0:
        ScoreMods += "TD"
    if mods & mods.RELAX > 0:
        ScoreMods += "RX"
    if mods & mods.RELAX2 > 0:
        ScoreMods += "AP"

    return ScoreMods
