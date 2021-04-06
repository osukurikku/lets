import json
import tornado.gen
import tornado.web

from objects import beatmap
from objects import scoreboard
from common.constants import privileges
from common.log import logUtils as log
from common.ripple import userUtils
from common.web import requestsManager
from constants import exceptions
from objects import glob
from common.constants import mods
from common.sentry import sentry

MODULE_NAME = "get_scores"
class handler(requestsManager.asyncRequestHandler):
	"""
	Handler for /web/osu-osz2-getscores.php
	"""
	@tornado.web.asynchronous
	@tornado.gen.engine
	@sentry.captureTornado
	def asyncGet(self):
		try:
			# Get request ip
			ip = self.getRequestIP()

			# Print arguments
			if glob.debug:
				requestsManager.printArguments(self)

			# TODO: Maintenance check

			# Check required arguments
			if not requestsManager.checkArguments(self.request.arguments, ["c", "f", "i", "m", "us", "v", "vv", "mods"]):
				raise exceptions.invalidArgumentsException(MODULE_NAME)

			# GET parameters
			md5 = self.get_argument("c")
			fileName = self.get_argument("f")
			beatmapSetID = self.get_argument("i")
			gameMode = self.get_argument("m")
			username = self.get_argument("us")
			password = self.get_argument("ha")
			scoreboardType = int(self.get_argument("v"))
			scoreboardVersion = int(self.get_argument("vv"))

			# Login and ban check
			userID = userUtils.getID(username)
			if userID == 0:
				raise exceptions.loginFailedException(MODULE_NAME, userID)
			if not userUtils.checkLogin(userID, password, ip):
				raise exceptions.loginFailedException(MODULE_NAME, username)
			if userUtils.check2FA(userID, ip):
				raise exceptions.need2FAException(MODULE_NAME, username, ip)
			# Ban check is pointless here, since there's no message on the client
			#if userHelper.isBanned(userID) == True:
			#	raise exceptions.userBannedException(MODULE_NAME, username)

			# Hax check
			if "a" in self.request.arguments:
				if int(self.get_argument("a")) == 1 and not userUtils.getAqn(userID):
					log.warning("Found AQN folder on user {} ({})".format(username, userID), "cm")
					userUtils.setAqn(userID)

			userSettings = glob.redis.get("kr:user_settings:{}".format(userID))
			if userSettings:
				userSettings = json.loads(userSettings)

			# Scoreboard type
			isDonor = userUtils.getPrivileges(userID) & privileges.USER_DONOR > 0
			country = False
			friends = False
			clan = False
			modsFilter = int(self.get_argument("mods"))
			if scoreboardType == 4:
				# Country leaderboard
				country = True
				if userSettings and userSettings.get("clan_top_enabled", False):
					clan = True
					country = False
			elif scoreboardType == 2:
				# Mods leaderboard, replace mods (-1, every mod) with "mods" GET parameters
				modsFilter = int(self.get_argument("mods"))

				# Disable automod (pp sort) if we are not donors
				# if not isDonor:
				# 	modsFilter = modsFilter & ~mods.AUTOPLAY
			elif scoreboardType == 3 and isDonor:
				# Friends leaderboard
				friends = True

			if (modsFilter > -1 and scoreboardType != 2) and \
			   (not (modsFilter&mods.RELAX) and not (modsFilter&mods.RELAX2)):
				modsFilter = -1

			# Console output
			fileNameShort = fileName[:32]+"..." if len(fileName) > 32 else fileName[:-4]
			log.info("Requested beatmap {} ({})".format(fileNameShort, md5))

			# Create beatmap object and set its data
			bmap = beatmap.beatmap(md5, beatmapSetID, gameMode, file_name=fileName)

			# Create leaderboard object, link it to bmap and get all scores
			sboard = scoreboard.scoreboard(username, gameMode, bmap, setScores=True, country=country, mods=modsFilter, friends=friends, clan=clan)

			# Data to return
			data = ""
			data += bmap.getData(sboard.totalScores, scoreboardVersion)
			data += sboard.getScoresData()
			self.write(data)

			# Send bancho notification if needed
			if modsFilter > -1:
				knowsPPLeaderboard = False if glob.redis.get("lets:knows_pp_leaderboard:{}".format(userID)) is None else True
				if modsFilter & mods.AUTOPLAY > 0 and not knowsPPLeaderboard:
					glob.redis.set("lets:knows_pp_leaderboard:{}".format(userID), "1", 1800)
					glob.redis.publish("peppy:notification", json.dumps({
						"userID": userID,
						"message": "Hi there! Scores are now sorted by PP. You can change scores sort mode by toggling the 'Auto' mod and filtering the leaderboard by Active mods. Note that this option is available only for donors and we don't recommend saving replays when the leaderboard is sorted by pp, due to some client limitations."
					}))


			# Datadog stats
			glob.dog.increment(glob.DATADOG_PREFIX+".served_leaderboards")
		except exceptions.need2FAException:
			self.write("error: 2fa")
		except exceptions.invalidArgumentsException:
			self.write("error: meme")
		except exceptions.userBannedException:
			self.write("error: ban")
		except exceptions.loginFailedException:
			self.write("error: pass")
