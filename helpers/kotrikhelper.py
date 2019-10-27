import datetime
from objects import glob

def zingonify(d):
    """
    Zingonifies a string

    :param d: input dict
    :return: zingonified dict as str
    """
    return "|".join(f"{k}:{v}" for k, v in d.items())

def toDotTicks(unixTime):
    '''
    New version of my fix.

    :param unixTime: unixTimeStamp
    '''

    unixStamp = datetime.datetime.fromtimestamp(unixTime)
    base = datetime.datetime(1, 1, 1, 0, 0, 0)
    delt = unixStamp-base
    return int(delt.total_seconds())*10000000

def getUserBadges(userID):
    '''
    This shit just returning all badges by UserID
    #22

    :param userID: user in-game ID
    '''

    response = glob.db.fetchAll(f"SELECT * FROM user_badges WHERE user = {userID}")

    badges = [item['id'] for item in response]
    return badges

cheat_ids = {
    1: 'ReLife|HqOsu is running',
    2: 'Console in BG is found',
    4: 'Unknown but strange',
    8: 'Invalid name?',
    16: 'Invalid file?',
    32: 'ReLife|HqOsu has loaded',
    64: 'AqnSdl2Loaded (lib for overlay)',
    128: 'AqnLibeay32Loaded (lib for SSL)'
}

def getHackByFlag(flag):
    if cheat_ids.get(flag, False):
        return cheat_ids[flag]
    else:
        return flag
