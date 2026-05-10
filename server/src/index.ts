import express from 'express';
import { SSEServerTransport } from '@modelcontextprotocol/sdk/server/sse.js';
import { AzureDevOpsClient } from './ado/client.js';
import { createServer } from './mcp.js';

const app = express();
app.use(express.json());

const sessions = new Map<string, SSEServerTransport>();

app.get('/health', (_req, res) => {
  res.json({ status: 'ok', server: 'azure-devops-mcp', sessions: sessions.size });
});

app.get('/sse', async (req, res) => {
  const pat = (req.headers.authorization ?? '').replace(/^Bearer\s+/i, '').trim();
  const org = (req.headers['x-ado-org'] as string ?? '').trim();
  const project = (req.headers['x-ado-project'] as string | undefined)?.trim();
  const team = (req.headers['x-ado-team'] as string | undefined)?.trim();

  if (!pat || !org) {
    res.status(401).json({ error: 'Authorization (PAT) and X-ADO-Org headers are required' });
    return;
  }

  const client = new AzureDevOpsClient(pat, org, project, team);
  const server = createServer(client);
  const transport = new SSEServerTransport('/messages', res);

  sessions.set(transport.sessionId, transport);
  res.on('close', () => sessions.delete(transport.sessionId));

  await server.connect(transport);
});

app.post('/messages', async (req, res) => {
  const sessionId = req.query.sessionId as string;
  const transport = sessions.get(sessionId);
  if (!transport) {
    res.status(404).json({ error: 'Session not found' });
    return;
  }
  await transport.handlePostMessage(req, res, req.body);
});

const port = Number(process.env.PORT ?? 3000);
app.listen(port, () => console.log(`azure-devops MCP server on :${port}`));
