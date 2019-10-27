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

# Thanks for this flags cmyui#0425
osu_flags = {
    'SpeedHackDetected': 2,
    'IncorrectModValue': 4,
    'MultipleOsuClients': 8,
    'ChecksumFailure': 16,
    'FlashlightChecksumIncorrect': 32,
    'FlashLightImageHack': 256,
    'SpinnerHack': 512,
    'TransparentWindow': 1024,
    'FastPress': 2048,
    'RawMouseDiscrepancy': 4096,
    'RawKeyboardDiscrepancy': 8192
}

def getHackByHexFlags(bit):
    s = []
    if bit & osu_flags['SpeedHackDetected']: s.append("SpeedHackDetected  (2)")
    if bit & osu_flags['IncorrectModValue']: s.append("IncorrectModValue  (4)") # should actually always flag
    if bit & osu_flags['MultipleOsuClients']: s.append("MultipleOsuClients (8)")
    if bit & osu_flags['ChecksumFailure']: s.append("ChecksumFailure (16)")
    if bit & osu_flags['FlashlightChecksumIncorrect']: s.append("FlashlightChecksumIncorrect (32)")
    #64
    #128
    if bit & osu_flags['FlashLightImageHack']: s.append("FlashLightImageHack (256)")
    if bit & osu_flags['SpinnerHack']: s.append("SpinnerHack (512)")
    if bit & osu_flags['TransparentWindow']: s.append("TransparentWindow (1024)")
    if bit & osu_flags['FastPress']: s.append("FastPress (2048)")
    if bit & osu_flags['RawMouseDiscrepancy']: s.append("RawMouseDiscrepancy (4096)")
    if bit & osu_flags['RawKeyboardDiscrepancy']: s.append("RawKeyboardDiscrepancy (8192)")
    return '\n'.join(s)

def getHackByFlag(flag):
    if cheat_ids.get(flag, False):
        return cheat_ids[flag]
    else:
        return flag
