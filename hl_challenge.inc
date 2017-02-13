/** Double-include prevention */
#if defined _hl_challenge_included
  #endinput
#endif
#define _hl_challenge_included

/**
 * Returns if a player is in their challenge. A player
 * is in their challenge when they are loaded into their 
 * arena. Do NOT use before Multi1v1_OnPostArenaRankingsSet
 * is called.
 *
 * @param client 	client index to check
 * @return       	true if client is in challenge
 */
native bool hl_isInChallenge(int client);


/**
 * Returns if a player is in the queue for the challenge.
 * A player is in the queue if they accepted the challenge
 * request and is waiting to be pushed into
 *
 * @param client 	client index to check
 * @return       	true if client is in queue
 */
native bool hl_isInChallengeQueue(int client);


/**
 * Returns the client's challenge partner, they must be
 * already in their challenge before you can use this.
 *
 * @param client 	client index to check
 * @return       	client's partner index
 */
native int hl_getChallengePartner(int client);

/**
 * Places two players into the challenge queue. To be
 * put into the same challenge in the next round.
 *
 * @param player1 	client index
 * @param player2 	client index
 * @return       	no return
 */
native void hl_placeInChallengeQueue(int player1, int player2);
 
 
 
 
/************************* FORWARDS ***********************/
 
/**
 * Called after all challenge players have been pushed to the
 * ranking queue. The last player in the array is not always
 * a player that's in a challenge. If the length of the array
 * is odd, then you know the last player is NOT in a challenge.
 * This is to ensure that whoever the challengers are, they 
 * will be in the same arena and the odd player will be the
 * remainder.
 *
 * @param 	rankingQueue 	adt array of client indexes
 * @return       			no return
 */
forward void hl_onRankingQueueBuilt(ArrayList rankingQueue)

/**
 * Called after a player has won the challenge and their cooldown has been set.
 *
 * @param 		winner 		client index
 * @param 		loser 		client index
 * @return       			no return
 */
forward void hl_onChallengeWon(int winner, int loser)


 public SharedPlugin __pl_hl_challenge  =
{
	name = "[Multi-1v1] Challenge",
	file = "hl_challenge.smx",
#if defined REQUIRE_PLUGIN
	required = 1
#else
	required = 0
#endif
};

#if !defined REQUIRE_PLUGIN
public __pl_hl_challenge_SetNTVOptional()
{
	MarkNativeAsOptional("hl_isInChallenge");
	MarkNativeAsOptional("hl_isInChallengeQueue");
	MarkNativeAsOptional("hl_getChallengePartner");
	MarkNativeAsOptional("hl_getChallengePartner");
	MarkNativeAsOptional("hl_placeInChallengeQueue");
}
#endif