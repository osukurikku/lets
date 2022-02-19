import os
import json

import tornado.gen
import tornado.web

from common.log import logUtils as log
from common.ripple import userUtils
from common.web import requestsManager
from constants import exceptions
from objects import glob
from common.sentry import sentry

from helpers import kotrikhelper

MODULE_NAME = "osu-session"


class handler(requestsManager.asyncRequestHandler):
    """
    Handler for /web/osu-session.php
    """

    @tornado.web.asynchronous
    @tornado.gen.engine
    @sentry.captureTornado
    def asyncPost(self):
        try:
            if glob.debug:
                requestsManager.printArguments(self)

            # Check user auth because of sneaky people
            if not requestsManager.checkArguments(self.request.arguments, ["u", "h", "action"]):
                raise exceptions.invalidArgumentsException(MODULE_NAME)

            username = self.get_argument("u")
            password = self.get_argument("h")
            action = self.get_argument("action")
            ip = self.getRequestIP()
            userID = userUtils.getID(username)
            if not userUtils.checkLogin(userID, password):
                raise exceptions.loginFailedException(MODULE_NAME, username)
            if userUtils.check2FA(userID, ip):
                raise exceptions.need2FAException(MODULE_NAME, username, ip)

            if action != "submit":
                self.write("Yield")
                return

            content = self.get_argument("content")
            try:
                contentDict = json.loads(content)
                kotrikhelper.setUserSession(userID, contentDict)
                self.write("Yield")
            except:
                self.write("Not Yet")

            return
        except exceptions.need2FAException:
            pass
        except exceptions.invalidArgumentsException:
            pass
        except exceptions.loginFailedException:
            pass
