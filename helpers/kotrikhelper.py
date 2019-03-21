def zingonify(d):
    """
    Zingonifies a string

    :param d: input dict
    :return: zingonified dict as str
    """
    return "|".join(f"{k}:{v}" for k, v in d.items())

def toDotTicks(unixTime):
    """
    I fucking blows, peppy and ripple thx

    :param unixTime: UnixTimeStamp
    """
    dotTicksBase = 621355968000000000
    return (10000000*1542296830)+dotTicksBase
