import tornado.gen
import tornado.web

from common.ripple import userUtils
from common.web import requestsManager
from secret.discord_hooks import Webhook
from objects import glob
from helpers import kotrikhelper

MODULE_NAME = "lastFMHandler"


class handler(requestsManager.asyncRequestHandler):
    """
    Handler for /web/lastfm.php

    Handler by @KotRikD
    Enum values by @Enjuu and @Cyuubi
    """

    @tornado.web.asynchronous
    @tornado.gen.engine
    def asyncGet(self):
        webhook = Webhook(
            glob.conf.config["discord"]["ahook"],
            color=0xC32C74,
            footer="stupid anticheat",
        )

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
        cheat_flags = kotrikhelper.getHackByFlag(arguments_cheat)
        webhook.set_title(title=f"Catched some cheater {username} ({userID})")
        if type(cheat_flags) in [list, tuple]:
            # OUGH OUGH CALL THE POLICE! WE CATCHED SOME SHIT
            # LET'S SEND THIS TO POLICE
            webhook.set_desc(
                f'This body catched with flag {arguments_cheat}\nIn enuming: {",".join(cheat_flags)}'
            )
        else:
            webhook.set_desc(f"This body catched with undefined flag {arguments_cheat}")

        webhook.set_footer(text="sended by lastFMHandler")
        webhook.post()
        # Ask cheater to leave game(no i just kill him client ;d)
        glob.redis.publish("kotrik:hqosu", userID)

        return self.write("-3")
