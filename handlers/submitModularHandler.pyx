import collections
import json
import os
import sys
import traceback
from urllib.parse import urlencode

import requests
import tornado.gen
import tornado.web

import secret.achievements.utils
from common import generalUtils
from common.constants import gameModes
from common.constants import mods
from common.log import logUtils as log
from common.ripple import userUtils
from common.web import requestsManager
from constants import exceptions
from constants import rankedStatuses
from helpers import aeshelper
from helpers import leaderboardHelper
from helpers import kotrikhelper
from objects import beatmap
from objects import glob
from objects import score
from objects import scoreboard

from secret import achievements, butterCake
from secret.discord_hooks import Webhook

MODULE_NAME = "submit_modular"
class handler(requestsManager.asyncRequestHandler):
	"""
	Handler for /web/osu-submit-modular.php
	"""
	@tornado.web.asynchronous
	@tornado.gen.engine
	#@sentry.captureTornado
	def asyncPost(self):
		try:
			# Resend the score in case of unhandled exceptions
			keepSending = True

			# Get request ip
			ip = self.getRequestIP()

			# Print arguments
			if glob.debug:
				requestsManager.printArguments(self)

			# Check arguments
			if not requestsManager.checkArguments(self.request.arguments, ["score", "iv", "pass", "x", "s", "osuver"]):
				raise exceptions.invalidArgumentsException(MODULE_NAME)

			# TODO: Maintenance check

			# Get parameters and IP
			scoreDataEnc = self.get_argument("score")
			iv = self.get_argument("iv")
			password = self.get_argument("pass")
			ip = self.getRequestIP()

			# Get bmk and bml (notepad hack check)
			if "bmk" in self.request.arguments and "bml" in self.request.arguments:
				bmk = self.get_argument("bmk")
				bml = self.get_argument("bml")
			else:
				bmk = None
				bml = None

			# Get right AES Key
			if "osuver" in self.request.arguments:
				aeskey = "osu!-scoreburgr---------{}".format(self.get_argument("osuver"))
			else:
				aeskey = "h89f2-890h2h89b34g-h80g134n90133"

			# Get score data
			log.debug("Decrypting score data...")
			scoreData = aeshelper.decryptRinjdael(aeskey, iv, scoreDataEnc, True).split(":")
			username = scoreData[1].strip()

			# Login and ban check
			userID = userUtils.getID(username)
			# User exists check
			if userID == 0:
				raise exceptions.loginFailedException(MODULE_NAME, userID)
			# Bancho session/username-pass combo check
			if not userUtils.checkLogin(userID, password, ip):
				raise exceptions.loginFailedException(MODULE_NAME, username)
			# 2FA Check
			if userUtils.check2FA(userID, ip):
				raise exceptions.need2FAException(MODULE_NAME, userID, ip)
			# Generic bancho session check
			#if not userUtils.checkBanchoSession(userID):
				# TODO: Ban (see except exceptions.noBanchoSessionException block)
			#	raise exceptions.noBanchoSessionException(MODULE_NAME, username, ip)
			# Ban check
			if userUtils.isBanned(userID):
				raise exceptions.userBannedException(MODULE_NAME, username)
			# Data length check
			if len(scoreData) < 16:
				raise exceptions.invalidArgumentsException(MODULE_NAME)

			if not "bmk" in self.request.arguments:
				raise exceptions.haxException(userID) # oldver check
			
			if int(scoreData[17][:8]) != int(self.get_argument("osuver")):
				self.write("error: version mismatch")
				return

			# checksum check
			#
			# NOT ITS WORKING, ALL FUCKING FLEX!
			#	
			securityHash = aeshelper.decryptRinjdael(aeskey, iv, self.get_argument("s"), True).strip()		
			isScoreVerfied = kotrikhelper.verifyScoreData(scoreData, securityHash, self.get_argument("sbk", ""))
			if not isScoreVerfied:
				raise exceptions.checkSumNotPassed(username, scoreData[0], scoreData[2], "checksum doesn't match")

			# Get restricted
			restricted = userUtils.isRestricted(userID)

			# Create score object and set its data
			log.info("{} has submitted a score on {}...".format(username, scoreData[0]))
			s = score.score()
			s.setDataFromScoreData(scoreData)
			oldStats = userUtils.getUserStats(userID, s.gameMode)

			# Set score stuff missing in score data
			s.playerUserID = userID

			# Get beatmap info
			beatmapInfo = beatmap.beatmap()
			beatmapInfo.setDataFromDB(s.fileMd5)

			# Calculating play time data!
			userQuit = self.get_argument("x") == "1"
			failTime = None
			_ft = self.get_argument("ft", "0")
			if not _ft.isdigit(): # bye abusers
				raise exceptions.invalidArgumentsException(MODULE_NAME)
			
			_st = self.get_argument("st", None)
			if not _st or not _st.isdigit():
				raise exceptions.checkSumNotPassed(username, scoreData[0], scoreData[2], f"obv cheater: st flag is not present (cherry hqOsu)")
			
			if beatmapInfo.hitLength != 0 and not userQuit and int(_ft) == 0:
				hitLength = beatmapInfo.hitLength // 1.5 if (s.mods & mods.DOUBLETIME) > 0 else beatmapInfo.hitLength // 0.75 if (s.mods & mods.HALFTIME) > 0 else beatmapInfo.hitLength
				if (int(_st)//1000) < int(hitLength):
					raise exceptions.checkSumNotPassed(username, scoreData[0], scoreData[2], f"prob timewarped: player was on map {int(_st)//1000} seconds when map length is {hitLength}")

			# Make sure the beatmap is submitted and updated
			if beatmapInfo.rankedStatus == rankedStatuses.NOT_SUBMITTED or beatmapInfo.rankedStatus == rankedStatuses.NEED_UPDATE or beatmapInfo.rankedStatus == rankedStatuses.UNKNOWN:
				log.debug("Beatmap is not submitted/outdated/unknown. Score submission aborted.")
				return

			failTime = int(_ft)
			failed = not userQuit and failTime

			s.calculatePlayTime(beatmapInfo.hitLength, failTime // 1000 if failed else False)
			kotrikhelper.updateUserPlayTime(userID, s.gameMode, s.playTime)

			# Calculate PP
			# NOTE: PP are std and mania only
			ppCalcException = None
			try:
				s.calculatePP()
			except Exception as e:
				# Intercept ALL exceptions and bypass them.
				# We want to save scores even in case PP calc fails
				# due to some rippoppai bugs.
				# I know this is bad, but who cares since I'll rewrite
				# the scores server again.
				log.error("Caught an exception in pp calculation, re-raising after saving score in db")
				s.pp = 0
				ppCalcException = e

			s.setCompletedStatus()

			oldBestScore = None
			if s.personalOldBestScore:
				oldBestScore = score.score()
				oldBestScore.setDataFromDB(s.personalOldBestScore)

			if beatmapInfo.rankedStatus >= rankedStatuses.LOVED and s.passed:
				s.pp = 0

			# Restrict obvious cheaters
			if ((not userUtils.isInPrivilegeGroup(userID, "Verified Legit Player")) and s.pp >= 850 and s.gameMode == gameModes.STD) and restricted == False:
				userUtils.restrict(userID)
				userUtils.appendNotes(userID, "Restricted due to too high pp gain ({}pp)".format(s.pp))
				log.warning("**{}** ({}) has been restricted due to too high pp gain **({}pp)**".format(username, userID, s.pp), "cm")

			# Check notepad hack
			if not bmk and not bml:
				# No bmk and bml params passed, edited or super old client
				#log.warning("{} ({}) most likely submitted a score from an edited client or a super old client".format(username, userID), "cm")
				pass
			elif bmk != bml and restricted == False:
				# bmk and bml passed and they are different, restrict the user
				userUtils.restrict(userID)
				userUtils.appendNotes(userID, "Restricted due to notepad hack")
				log.warning("**{}** ({}) has been restricted due to notepad hack".format(username, userID), "cm")
				return

			# Save score in db
			s.saveScoreInDB()

			# OH? Italian peperoni?
			# Ya-Ya, 100% peperoni
			# Ripple, i just clean code and comments
			if s.score < 0 or s.score > (2 ** 63) - 1:
				userUtils.ban(userID)
				userUtils.appendNotes(userID, "Banned due to negative score (score submitter)")

			# Make sure the score is not memed
			if s.gameMode == gameModes.MANIA and s.score > 1000000:
				userUtils.ban(userID)
				userUtils.appendNotes(userID, "Banned due to mania score > 1000000 (score submitter)")

			# Check for impossible mod combination
			if ((s.mods & mods.DOUBLETIME) > 0 and (s.mods & mods.HALFTIME) > 0) \
			or ((s.mods & mods.HARDROCK) > 0 and (s.mods & mods.EASY) > 0) \
			or ((s.mods & mods.RELAX) > 0 and (s.mods & mods.RELAX2) > 0) \
			or ((s.mods & mods.SUDDENDEATH) > 0 and (s.mods & mods.NOFAIL) > 0):
				userUtils.ban(userID)
				userUtils.appendNotes(userID, "Impossible mod combination {} (score submitter)".format(s.mods))

			# Save replay
			if s.passed and s.scoreID > 0 and s.completed == 3:
				if "score" in self.request.files:
					# Save the replay if it was provided
					log.debug("Saving replay ({})...".format(s.scoreID))
					replay = self.request.files["score"][0]["body"]
					with open(".data/replays/replay_{}.osr".format(s.scoreID), "wb") as f:
						f.write(replay)
				else:
					# Restrict if no replay was provided
					if not restricted:
						userUtils.restrict(userID)
						userUtils.appendNotes(userID, "Restricted due to missing replay while submitting a score.")
						log.warning("**{}** ({}) has been restricted due to not submitting a replay on map {}.".format(
							username, userID, s.fileMd5
						), "cm")

			# Make sure the replay has been saved (debug)
			if not os.path.isfile(".data/replays/replay_{}.osr".format(s.scoreID)) and s.completed == 3:
				log.error("Replay for score {} not saved!!".format(s.scoreID), "bunker")

			# Let the api know of this score
			if s.scoreID:
				glob.redis.publish("api:score_submission", s.scoreID)

				if s.gameMode == 0 and s.completed == 3:
					beat = beatmap.beatmap(s.fileMd5, 0)
					glob.redis.publish("kr:calc1", json.dumps({
						"score_id": s.scoreID,
						"map_id": beat.beatmapID,
						"user_id": s.playerUserID,
						"mods": s.mods
					}))

			# Re-raise pp calc exception after saving score, cake, replay etc
			# so Sentry can track it without breaking score submission
			if ppCalcException:
				raise ppCalcException

			# If there was no exception, update stats and build score submitted panel
			# We don't have to do that since stats are recalculated with the cron
			# Update beatmap playcount (and passcount)
			beatmap.incrementPlaycount(s.fileMd5, s.passed)

			# Get "before" stats for ranking panel (only if passed)
			if s.passed:
				# Get stats and rank
				oldUserData = glob.userStatsCache.get(userID, s.gameMode)
				oldRank = userUtils.getGameRank(userID, s.gameMode)

				# Try to get oldPersonalBestRank from cache
				oldPersonalBestRank = glob.personalBestCache.get(userID, s.fileMd5)
				if not oldPersonalBestRank:
					oldPersonalBestRank = -1

			# Always update users stats (total/ranked score, playcount, level, acc and pp)
			# even if not passed
			log.debug("Updating {}'s stats...".format(username))
			userUtils.updateStats(userID, s)

			# Get "after" stats for ranking panel
			# and to determine if we should update the leaderboard
			# (only if we passed that song)
			if s.passed:
				# Get new stats
				newUserData = userUtils.getUserStats(userID, s.gameMode)
				glob.userStatsCache.update(userID, s.gameMode, newUserData)

				# Update leaderboard (global and country) if score/pp has changed
				if s.completed == 3 and newUserData["pp"] != oldUserData["pp"]:
					leaderboardHelper.update(userID, newUserData["pp"], s.gameMode)
					leaderboardHelper.updateCountry(userID, newUserData["pp"], s.gameMode)

			# TODO: Update total hits and max combo
			# Update latest activity
			userUtils.updateLatestActivity(userID)

			# IP log
			userUtils.IPLog(userID, ip)

			# Score submission and stats update done
			log.debug("Score submission and user stats update done!")

			# Score has been submitted, do not retry sending the score if
			# there are exceptions while building the ranking panel
			keepSending = False

			# At the end, check achievements
			if s.passed:
				secret.achievements.utils.unlock_achievements(s, beatmapInfo, newUserData)

			# Output ranking panel only if we passed the song
			# and we got valid beatmap info from db
			if beatmapInfo and beatmapInfo != False and s.passed:
				log.debug("Started building ranking panel")

				# Trigger bancho stats cache update
				glob.redis.publish("peppy:update_cached_stats", userID)

				# checking mods for next code part
				isRelax = s.mods&mods.RELAX
				isAutopilot = s.mods&mods.RELAX2

				# Get personal best after submitting the score
				newScoreboard = scoreboard.scoreboard(username, s.gameMode, beatmapInfo, False, mods=(s.mods if isRelax or isAutopilot else 0))
				newScoreboard.setScores(limitQuery=2)

				# Get rank info (current rank, pp/score to next rank, user who is 1 rank above us)
				rankInfo = leaderboardHelper.getRankInfo(userID, s.gameMode)

				beatmapStat = collections.OrderedDict([
					('beatmapId', beatmapInfo.beatmapID),
					('beatmapSetId', beatmapInfo.beatmapSetID),
					('beatmapPlaycount', beatmapInfo.playcount),
					('beatmapPasscount', beatmapInfo.passcount),
					('approvedDate', f"{beatmapInfo.approvedDate}" if beatmapInfo.approvedDate else "")
				])

				# Output dictionary
				output = collections.OrderedDict([
					('chartId', 'overall'),
					('chartName', 'Overall Ranking'),
					('chartEndDate', ""),
					('rankedScoreBefore', oldUserData["rankedScore"]),
					('rankedScoreAfter', newUserData["rankedScore"]),
					('totalScoreBefore', oldUserData["totalScore"]),
					('totalScoreAfter', newUserData["totalScore"]),
					('maxComboBefore', oldBestScore.maxCombo if oldBestScore else ""),
					('maxComboAfter', s.maxCombo if not oldBestScore else (s.maxCombo if oldBestScore and oldBestScore.maxCombo<s.maxCombo else oldBestScore.maxCombo)),
					('accuracyBefore', round(float(oldUserData["accuracy"]), 2)),
					('accuracyAfter', round(float(newUserData["accuracy"]), 2)),
					('ppBefore', oldStats["pp"]),
					('ppAfter', newUserData["pp"]),
					('rankBefore', oldRank),
					('rankAfter', rankInfo["currentRank"]),
					('toNextRank', rankInfo["difference"]),
					('toNextRankUser', rankInfo["nextUsername"]),
					('achievements', ""),
					('achievements-new', ""),
					('onlineScoreId', s.scoreID)
				])
				
				outputBeatmap = collections.OrderedDict([
					('chartId', "beatmap"),
					('chartUrl', f"https://kurikku.pw/b/{beatmapInfo.beatmapID}"),
					('chartName', "Beatmap Ranking"),
					('rankBefore', oldPersonalBestRank if oldPersonalBestRank > 0 else ""),
					('rankAfter', newScoreboard.personalBestRank),
					('maxComboBefore', oldBestScore.maxCombo if oldBestScore else ""),
					('maxComboAfter', s.maxCombo),
					('rankedScoreBefore', oldBestScore.score if oldBestScore else ""),
					('rankedScoreAfter', s.score),
					('accuracyBefore', round(oldBestScore.accuracy*100, 2) if oldBestScore else ""),
					('accuracyAfter', round(s.accuracy*100, 2)),
					('ppBefore', oldBestScore.pp if oldBestScore else ""),
					('ppAfter', s.pp),
					('achievements-new', ""),
					('onlineScoreId', s.scoreID)
				])
				# Build final string
				msg = "\n".join(kotrikhelper.zingonify(x) for x in [beatmapStat, outputBeatmap, output])

				# Some debug messages
				log.debug("Generated output for online ranking screen!")
				log.debug(msg)
				
				if isRelax:
					messages = [
						f" Achieved #{newScoreboard.personalBestRank} rank with RX on ",
						"[https://kurikku.pw/?u={} {}] achieved rank #1 with RX on [https://osu.ppy.sh/b/{} {}] ({})",
						"{} has lost #1 RX on "
					]
				elif isAutopilot:
					messages = [
						f" Achieved #{newScoreboard.personalBestRank} rank with AP on ",
						"[https://kurikku.pw/?u={} {}] achieved rank #1 with AP on [https://osu.ppy.sh/b/{} {}] ({})",
						"{} has lost #1 AP on "
					]
				else:
					messages = [
						f" Achieved #{newScoreboard.personalBestRank} rank on ",
						"[https://kurikku.pw/?u={} {}] achieved rank #1 on [https://osu.ppy.sh/b/{} {}] ({})",
						"{} has lost #1 on "
					]

				if s.completed == 3 and restricted == False and beatmapInfo.rankedStatus >= rankedStatuses.RANKED and newScoreboard.personalBestRank > oldPersonalBestRank:
					if newScoreboard.personalBestRank == 1 and len(newScoreboard.scores) > 2:
						#woohoo we achieved #1, now we should say to #2 that he sniped!						
						userUtils.logUserLog(messages[2].format(newScoreboard.scores[2].playerName), s.fileMd5, newScoreboard.scores[2].playerUserID, s.gameMode, s.scoreID)

					userLogMsg = messages[0]
					userUtils.logUserLog(userLogMsg, s.fileMd5, userID, s.gameMode, s.scoreID)

				if newScoreboard.personalBestRank == 1 and s.completed == 3 and restricted == False:
					annmsg = messages[1].format(
						userID,
						username.encode().decode("ASCII", "ignore"),
						beatmapInfo.beatmapID,
						beatmapInfo.songName.encode().decode("ASCII", "ignore"),
						gameModes.getGamemodeFull(s.gameMode)
					)

					requests.get("{}/api/v1/fokabotMessage".format(glob.conf.config["server"]["banchourl"]), params={
						"k": glob.conf.config["server"]["apikey"],
						"to": "#announce",
						"msg": annmsg
					})

				if s.completed == 3 and restricted == False and beatmapInfo.rankedStatus >= rankedStatuses.RANKED and s.pp > 10:
					glob.redis.publish("scores:new_score", json.dumps({
						"gm":s.gameMode,
						"user":{"username":username, "userID": userID, "rank":newUserData["gameRank"],"oldaccuracy":oldStats["accuracy"],"accuracy":newUserData["accuracy"], "oldpp":oldStats["pp"],"pp":newUserData["pp"]},
						"score":{"scoreID": s.scoreID, "mods":s.mods, "accuracy":s.accuracy, "missess":s.cMiss, "combo":s.maxCombo, "pp":s.pp, "rank":newScoreboard.personalBestRank, "ranking":s.rank},
						"beatmap":{"beatmapID": beatmapInfo.beatmapID, "beatmapSetID": beatmapInfo.beatmapSetID, "max_combo":beatmapInfo.maxCombo, "song_name":beatmapInfo.songName}
					}))

				# Write message to client
				self.write(msg)
			else:
				# No ranking panel, send just "ok"
				self.write("ok")

			# Send username change request to bancho if needed
			# (key is deleted bancho-side)
			newUsername = glob.redis.get(f"ripple:change_username_pending:{userID}")
			if newUsername:
				log.debug(f"Sending username change request for user {userID} to Bancho")
				glob.redis.publish("peppy:change_username", json.dumps({
					"userID": userID,
					"newUsername": newUsername.decode("utf-8")
				}))

			# Datadog stats
			glob.dog.increment(glob.DATADOG_PREFIX+".submitted_scores")
		except exceptions.invalidArgumentsException:
			self.write("error: dup")
		except exceptions.loginFailedException:
			self.write("error: pass")
		except exceptions.need2FAException:
			# Send error pass to notify the user
			# resend the score at regular intervals
			# for users with memy connection
			self.set_status(408)
			self.write("error: 2fa")
		except exceptions.userBannedException:
			self.write("error: ban")
		except exceptions.noBanchoSessionException:
			# We don't have an active bancho session.
			# Don't ban the user but tell the client to send the score again.
			# Once we are sure that this error doesn't get triggered when it
			# shouldn't (eg: bancho restart), we'll ban users that submit
			# scores without an active bancho session.
			# We only log through schiavo atm (see exceptions.py).
			self.set_status(408)
			self.write("error: pass")
		except exceptions.haxException as e:
			self.write("error: oldver")
			glob.redis.publish("peppy:notification", json.dumps({
				'userID': e.userID,
				"message": "Sorry, you use outdated/bad osu!version. Please update game to submit scores!"
			}))
		except exceptions.checkSumNotPassed as e:
			webhook = Webhook(glob.conf.config["discord"]["ahook"],
                  color=0xc32c74,
                  footer="stupid anticheat")				
			userID = userUtils.getID(e.who)
			webhook.set_title(title=f"Catched some cheater {e.who} ({userID})")
			webhook.set_desc(f'{e.additional_notification}')
			webhook.set_footer(text="sended by submit-moodular-cuckold-checker")
			webhook.post()
			self.write("error: checksum")
		except:
			# Try except block to avoid more errors
			try:
				log.error("Unknown error in {}!\n```{}\n{}```".format(MODULE_NAME, sys.exc_info(), traceback.format_exc()))
				if glob.sentry:
					yield tornado.gen.Task(self.captureException, exc_info=True)
			except:
				pass

			# Every other exception returns a 408 error (timeout)
			# This avoids lost scores due to score server crash
			# because the client will send the score again after some time.
			if keepSending:
				self.set_status(408)
