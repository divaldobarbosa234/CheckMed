import type { PhilMood } from "./Phil";

export const LINES: Record<PhilMood, string> = {
  happy: "Hey — I’m Phil. We’ll check this together, one dose at a time.",
  excited: "Taken! Tiny win — I’m proud of you.",
  thinking: "Reading the prescription… you still get the final say.",
  wink: "No guilt. Just a tap — take it now, or skip and tell me later.",
  sad: "It’s getting late. I’m still here.",
  sick: "Rough day. We’ll go gentle.",
  love: "You showed up. That matters.",
  sleepy: "I know. It’s early. Then we can both sleep.",
  doctor: "Let’s review every line against the paper.",
  listen: "Lining up names and times…",
  cheer: "Today’s plan is done. See you tomorrow.",
  worry: "Time for Amoxicillin. I’m with you.",
};

export const STAGES = [
  { id: "splash", label: "Splash", hint: "Flash page" },
  { id: "home", label: "Home", hint: "Greeting · connection" },
  { id: "alarm", label: "Alarm", hint: "AlarmKit + Phil" },
  { id: "widget", label: "Widget", hint: "Mood matches color" },
  { id: "processing", label: "Processing", hint: "OCR companion" },
  { id: "nudge", label: "Nudge", hint: "No guilt reminder" },
  { id: "celebrate", label: "Dose taken", hint: "Phil win" },
] as const;

export type StageId = (typeof STAGES)[number]["id"];

export type WidgetTone = {
  id: string;
  mood: PhilMood;
  crop: "full" | "peek";
  bg: string;
  ink: string;
  muted: string;
  badge: string;
  title: string;
  line: string;
};

export const WIDGET_TONES: WidgetTone[] = [
  { id: "ready", mood: "happy", crop: "full", bg: "#58CC02", ink: "#fff", muted: "rgba(255,255,255,.8)", badge: "🔥 4", title: "Ready?", line: "Next dose 16:00" },
  { id: "taken", mood: "excited", crop: "full", bg: "#FFD400", ink: "#3D2A00", muted: "rgba(61,42,0,.7)", badge: "🔥 4", title: "Taken!", line: "Tiny win" },
  { id: "think", mood: "thinking", crop: "full", bg: "#1CB0F6", ink: "#fff", muted: "rgba(255,255,255,.8)", badge: "3", title: "Today’s plan", line: "3 medicines" },
  { id: "sleep", mood: "sleepy", crop: "full", bg: "#4B3F72", ink: "#fff", muted: "rgba(255,255,255,.75)", badge: "08:00", title: "It's early", line: "Amoxicillin" },
  { id: "due", mood: "worry", crop: "full", bg: "#FF9600", ink: "#fff", muted: "rgba(255,255,255,.85)", badge: "now", title: "Time", line: "500 mg waiting" },
  { id: "late", mood: "sad", crop: "full", bg: "#CE82FF", ink: "#fff", muted: "rgba(255,255,255,.85)", badge: "🔥 4", title: "Getting late", line: "I’m still here" },
  { id: "doc", mood: "doctor", crop: "full", bg: "#14532D", ink: "#ECFDF3", muted: "rgba(236,253,243,.75)", badge: "Dr", title: "Review", line: "You confirm" },
  { id: "listen", mood: "listen", crop: "full", bg: "#5B3CC4", ink: "#fff", muted: "rgba(255,255,255,.8)", badge: "OCR", title: "Reading…", line: "Names & times" },
  { id: "nudge", mood: "wink", crop: "full", bg: "#FF86D0", ink: "#fff", muted: "rgba(255,255,255,.85)", badge: "👋", title: "Hey", line: "Just a tap" },
  { id: "love", mood: "love", crop: "full", bg: "#FF4B6A", ink: "#fff", muted: "rgba(255,255,255,.85)", badge: "♥", title: "Care", line: "You showed up" },
  { id: "sick", mood: "sick", crop: "full", bg: "#7EC8FF", ink: "#083C60", muted: "rgba(8,60,96,.7)", badge: "easy", title: "Gentle day", line: "No lecture" },
  { id: "cheer", mood: "cheer", crop: "peek", bg: "#2B580C", ink: "#fff", muted: "rgba(255,255,255,.8)", badge: "3/3", title: "Done", line: "See you tomorrow" },
];
