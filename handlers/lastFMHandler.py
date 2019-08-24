import tornado.gen
import tornado.web

from common.ripple import userUtils
from common.web import requestsManager
from secret.discord_hooks import Webhook
from objects import glob

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

webhook = Webhook(glob.conf.config["discord"]["ahook"],
                  color=0xc32c74,
                  footer="stupid anticheat")


MODULE_NAME = "lastFMHandler"
class handler(requestsManager.asyncRequestHandler):
    """
    Handler for /web/lastfm.php

    Handler by @KotRikD
    Enum values by @Enjuu and @Cyuubi
    """
    @tornado.web.asynchronous
    @tornado.gen.engine
    @sentry.captureTornado
    def asyncGet(self):
        ip = self.getRequestIP()
        if not requestsManager.checkArguments(self.request.arguments, ["b", "ha", "us"]):
            return self.write("error: gimme more arguments")

        username = self.get_argument("us")
        password = self.get_argument("ha")
        beatmap_ban = self.get_argument("b", None)

        userID = userUtils.getID(username)
        if userID == 0:
            return self.write("error: user is unknown")
        if not userUtils.checkLogin(userID, password, ip):
            return self.write("error: this dude is not authorized. BAN!")
        if not beatmap_ban or beatmap_ban and not beatmap_ban.startswith("a"):
            return self.write("-3")

        arguments_cheat = beatmap_ban[1:]
        if not arguments_cheat.isdigit():
            return self.write("error: srsly?")

        arguments_cheat = int(arguments_cheat)
        # Let's try found something
        cheat_id = cheat_ids.get(arguments_cheat, -1)
        if cheat_id == -1:
            return self.write("-3")

        # OUGH OUGH CALL THE POLICE! WE CATCHED SOME SHIT
        # LET'S SEND THIS TO POLICE
        webhook.set_title(title=f"Catched some cheater {username} ({userID})")
        webhook.set_desc(f'This body catched with flag {arguments_cheat}\nIn enuming: {cheat_id}')
        webhook.post()

        return self.write("-3")
