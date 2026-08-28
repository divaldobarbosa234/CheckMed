import { useMemo, useState } from 'react';

import type { CompanionMood } from '@/design/Character';
import type { PathNodeData, PathStatus } from '@/design/PathNode';

import { COMPANION_NAME, MOCK_TODAY_PATH } from './mockPath';

function advancePath(nodes: PathNodeData[], id: string, status: Extract<PathStatus, 'done' | 'skipped'>) {
  const index = nodes.findIndex((node) => node.id === id);
  return nodes.map((node, i) => {
    if (node.id === id) return { ...node, status };
    if (i === index + 1 && node.status === 'locked') return { ...node, status: 'current' as const };
    return node;
  });
}

export function useTodayPath() {
  const [nodes, setNodes] = useState<PathNodeData[]>(MOCK_TODAY_PATH);
  const [mood, setMood] = useState<CompanionMood>('idle');

  const current = nodes.find((node) => node.status === 'current');
  const completed = nodes.filter((node) => node.status === 'done' || node.status === 'skipped').length;
  const pathComplete = nodes.every((node) => node.status === 'done' || node.status === 'skipped');

  const bubble = useMemo(() => {
    if (pathComplete) {
      return `Path complete — that's the loop. I'm ${COMPANION_NAME}, and I'll host tomorrow too.`;
    }
    if (mood === 'celebrate' && current) {
      return `Logged. That's how we keep the streak warm. Next up: ${current.medicine} at ${current.time}.`;
    }
    if (mood === 'skip' && current) {
      return `No sweat. We'll try the next one together — ${current.medicine} at ${current.time}.`;
    }
    if (current) {
      return `I'm ${COMPANION_NAME}. Today is a path, not a table. Ready for ${current.medicine} at ${current.time}?`;
    }
    return `I'm ${COMPANION_NAME}. Scan a paper when you want me to organize it with you.`;
  }, [current, mood, pathComplete]);

  function takeCurrent() {
    if (!current) return;
    setNodes((prev) => advancePath(prev, current.id, 'done'));
    setMood('celebrate');
  }

  function skipCurrent() {
    if (!current) return;
    setNodes((prev) => advancePath(prev, current.id, 'skipped'));
    setMood('skip');
  }

  return {
    nodes,
    mood: pathComplete ? 'complete' : mood,
    bubble,
    current,
    completed,
    total: nodes.length,
    pathComplete,
    takeCurrent,
    skipCurrent,
  };
}
