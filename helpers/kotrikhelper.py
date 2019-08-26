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
