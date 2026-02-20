const { TableClient } = require("@azure/data-tables");

const TABLE_NAME = "leaderboard";
const TOP_N = 10;
const VALID_GAMES = new Set(["depthcharge", "torpedoalley", "navalstrike"]);

function getClient() {
  return TableClient.fromConnectionString(
    process.env.STORAGE_CONNECTION_STRING,
    TABLE_NAME
  );
}

module.exports = async function (context, req) {
  if (req.method === "GET") {
    return handleGet(context, req);
  }
  if (req.method === "POST") {
    return handlePost(context, req);
  }
  context.res = { status: 405, body: "Method Not Allowed" };
};

// GET /api/scores?game=depthcharge  →  top 10 scores for that game
async function handleGet(context, req) {
  const game = (req.query.game || "").toLowerCase();
  if (!VALID_GAMES.has(game)) {
    context.res = { status: 400, body: "Invalid game name" };
    return;
  }

  try {
    const client = getClient();
    const entities = client.listEntities({
      queryOptions: { filter: `PartitionKey eq '${game}'` },
    });

    const scores = [];
    for await (const entity of entities) {
      scores.push({
        initials: entity.initials,
        score: entity.score,
        timestamp: entity.timestamp,
      });
    }

    scores.sort((a, b) => b.score - a.score);
    context.res = {
      status: 200,
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(scores.slice(0, TOP_N)),
    };
  } catch (err) {
    context.log.error("GET /api/scores error:", err.message);
    context.res = { status: 500, body: "Internal Server Error" };
  }
}

// POST /api/scores  body: { game, initials, score }
async function handlePost(context, req) {
  const { game, initials, score } = req.body || {};

  if (!VALID_GAMES.has((game || "").toLowerCase())) {
    context.res = { status: 400, body: "Invalid game name" };
    return;
  }
  const cleanInitials = String(initials || "").toUpperCase().replace(/[^A-Z0-9]/g, "").slice(0, 3);
  if (!cleanInitials) {
    context.res = { status: 400, body: "Initials required (up to 3 letters)" };
    return;
  }
  const numScore = parseInt(score, 10);
  if (isNaN(numScore) || numScore < 0) {
    context.res = { status: 400, body: "Score must be a non-negative integer" };
    return;
  }

  try {
    const client = getClient();
    // Row key: timestamp ensures uniqueness; sort is done on read
    const rowKey = `${Date.now()}-${Math.random().toString(36).slice(2, 7)}`;
    await client.createEntity({
      partitionKey: game.toLowerCase(),
      rowKey,
      initials: cleanInitials,
      score: numScore,
    });
    context.res = { status: 201, body: JSON.stringify({ initials: cleanInitials, score: numScore }) };
  } catch (err) {
    context.log.error("POST /api/scores error:", err.message);
    context.res = { status: 500, body: "Internal Server Error" };
  }
}
