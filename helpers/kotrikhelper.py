import datetime
import json
import hashlib
import string
import io
from common.constants import gameModes
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


def updateUserPlayTime(userID, gameMode, playTime):
    '''
        Some python guide for ripple-codders on python3.6+

        You can forget about '{}'.format(value) via f'{value}'!

        :param userID int: userID of user which you want update
        :param gameMode int: gameMode which you want update
        :param playTime int: how many seconds you want add
        :return bool: Boolean True
    '''
    modeForDB = gameModes.getGameModeForDB(gameMode)
    glob.db.execute(f"UPDATE users_stats SET playtime_{modeForDB} = playtime_{modeForDB} + %s WHERE id = %s", [playTime, userID])
    return True


def verifyScoreData(scoreData, securityHash):
    nonHashedString = "chickenmcnuggets{}o15{}{}smustard{}{}uu{}{}{}{}{}{}{}Q{}{}{}{}{}".format(
        int(scoreData[4])+int(scoreData[3]),
        int(scoreData[5]),
        int(scoreData[6]),
        int(scoreData[7]),
        int(scoreData[8]),
        scoreData[0],
        int(scoreData[10]),
        scoreData[11],
        scoreData[1].strip(),
        int(scoreData[9]),
        scoreData[12],
        int(scoreData[13]),
        scoreData[14],
        int(scoreData[15]),
        scoreData[17][0:8],
        int(scoreData[16]),
        ''.join(filter(lambda x: x in string.printable, securityHash))
    )

    hashedString = str(hashlib.md5(nonHashedString.encode()).hexdigest())
    if hashedString == scoreData[2]:
        return True
    
    return False


def getUserBadges(userID):
    '''
    This shit just returning all badges by UserID
    #22

    :param userID: user in-game ID
    '''

    response = glob.db.fetchAll(
        f"SELECT * FROM user_badges WHERE user = {userID}")

    badges = [item['id'] for item in response]
    return badges


def isPPOverScore(userID):
    '''
        it's literally nothing!
    '''

    response = glob.db.fetch("SELECT pp_over_score FROM users_stats WHERE id = %s LIMIT 1", [userID])
    if not response:
        return True

    return bool(response['pp_over_score'])


def setUserSession(userID: int, sessionObj: dict):
    '''
        Some shit for update osu-session.php
    '''

    glob.db.execute("UPDATE users SET last_session = %s WHERE id = %s", [
                    json.dumps(sessionObj), userID])
    return True

def getUserIdByIP(ip: str) -> int:
    '''
        Getting user by IP, funny yeah?
    '''
    users = glob.redis.keys("peppy:sessions:*")
    all_values = []
    for user in users:
        ipMember = glob.redis.smembers(user.decode())
        all_values.append(list(ipMember)[0])

    user_id = 0

    i = 0
    for user in users:
        if all_values[i].decode() == ip:
            user_id = int(user.decode().replace('peppy:sessions:', ""))
            break
        i+=1

    if user_id == 0:
        return 0

    return user_id

def getUserBGs(uid: int) -> list:
    '''
        I'm tired, but this function returns the list with custom bgs!
    '''
    bgs = glob.db.fetch("SELECT custom_bgs FROM user_kotrik_settings WHERE uid = %s", [uid])
    if not bgs:
        return []
    
    return bgs['custom_bgs'].split("|")

cheat_ids = {
    1: 'ReLife|HqOsu is running',
    2: 'Console in BG is found',
    4: 'Wrong mod combination',
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
