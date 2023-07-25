// Basic example of using rrweb record and rrweb-player with React.
// 
// We provide two screens, one with some example elements to interact with,
// and one which provides a list of recordings to play back. Recordings are
// defined as a list of events that are grouped by a session ID. Events are
// persisted to IndexedDB, and then loaded from there when the user selects
// a recording to play back.
//
// The default screen is the recordings screen, and there is a button you can
// click to be taken to the example elements screen in a new tab. on loading the
// example elements screen, we generate a new session ID. This session ID is
// passed to rrweb.record() so that all events are grouped by this session ID.
//
// We use React router to provide the two screens, and we use the rrweb-player
// to play back the recordings.
//
// We use Uno CSS for styling, with the default tailwind theme.

import rrwebReplayer from 'rrweb-player';
import * as rrweb from 'rrweb';
import 'rrweb-player/dist/style.css';
import { useRef, useEffect, useState } from 'react';
import { v4 } from 'uuid';
import { HashRouter, Routes, Route, Link, useParams, Navigate } from "react-router-dom";
import { IDBPDatabase, openDB } from 'idb';
import React from 'react';

const API_ROOT = 'https://5c39zvs723.execute-api.us-east-1.amazonaws.com/prod/'

// For recordings storage we use IndexedDB. We use the idb library to provide
// a simple wrapper around IndexedDB. The IndexedDB includes a single store
// called 'recordings' which contains all the recordings events. Each event
// is stored as a separate object. They are of the form:
//
// {
//   sessionId: string,
//   rrwebEvent: rrweb.EventType,
//   sequence: number,
// }
//
// The keys are the sessionId plus a sequence number, e.g.:
//
// 1234-0
// 1234-1
// 1234-2
//
// The sequence number is used to order the events.
//
// We open the IndexedDB in the RecordingsDbProvider, and then provide the
// recordings and events to the RecordingsListPage and RRWebRecordedPage
// components via a React context.
//
// If the IndexedDB version needs updating, we create the 'recordings' object
// store.

const RECORDINGS_DATABASE_NAME = 'rrweb-recordings';
const RECORDING_EVENT_STORE_NAME = 'recordings';
const RecordingsDbContext = React.createContext<IDBPDatabase | null>(null);

const RecordingsDbProvider = ({ children }: { children: React.ReactNode }) => {
  // Open the IndexedDB using the idb library.
  const [recordingsDb, setRecordingsDb] = useState<IDBPDatabase | null>(null);

  useEffect(() => {
    // Open the IndexedDB. The IndexedDB includes a single store called
    // 'recordings' which contains all the recordings events. Each event
    // is stored as a separate object.
    openDB(RECORDINGS_DATABASE_NAME, 1, {
      upgrade(db, oldVersion) {
        // Create the recordings store if 1 is between oldVersion and
        // newVersion.
        if (oldVersion < 1) {
          db.createObjectStore('recordings');
          console.info('Created recordings IndexedDB')
        }
      },
    }).then((db) => {
      setRecordingsDb(db);
    }).catch((err) => {
      console.error(err);
    });
  }, []);

  return (
    <RecordingsDbContext.Provider value={recordingsDb}>
      {recordingsDb ? children : 'Loading...'}
    </RecordingsDbContext.Provider>
  );
}

function App() {
  // At the top level, we use React router to provide two screens, one for
  // the example elements and rrweb recording (RRWebRecordedPage), and one for
  // the recordings list and playback (RecordingsListPage).
  return (
    <RecordingsDbProvider>
      <HashRouter>
        <Routes>
          <Route path="/" element={<Navigate to="/replay/" />} />
          <Route path="/replay/" element={<RecordingsListPage />} />
          <Route path="/replay/:sessionId" element={<RecordingsListPage />} />
          <Route path="/session" element={<RRWebRecordedPage />} />
        </Routes>
      </HashRouter>
    </RecordingsDbProvider>
  );
}

const useRecordingsDb = () => {
  // Get the IndexedDB from the context.
  const recordingsDb = React.useContext(RecordingsDbContext);

  if (!recordingsDb) {
    throw new Error('Recordings store not available');
  }

  return recordingsDb;
}

const RRWebRecordedPage = () => {
  // A page on which there are some elements to interact with. The page
  // creates a new session ID on load, and then records all events with
  // that session ID into IndexedDB. To give some kind or order, we prefix the
  // sessionID with the current timestamp in an iso1806 format to it's not too 
  // hard to find the most recent session ID. We use a ref to store the session
  // ID so that it doesn't change on re-renders.
  const sessionId = useRef(`${new Date().toISOString()}-${v4()}`);
  const counterRef = useRef(0);

  // Start rrweb recording on load.
  useEffect(() => {
    // Create a recording with a PUT to /recordings/{sessionId}.
    fetch(`${API_ROOT}/recordings/${sessionId.current}`, {
      method: 'PUT',
      mode: 'cors',
      headers: {
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        sessionId: sessionId.current,
      })
    });
    rrweb.record({
      async emit(event) {
        // Persist the event to IndexedDB.
        const sequence = counterRef.current++;
        // Send the event to the backend. We need to consider CORS here. We also
        // need to ensure we have set the correct content-type header.
        await fetch(`${API_ROOT}/recordings/${sessionId.current}/events`, {
          method: 'POST',
          mode: 'cors',
          headers: {
            'Content-Type': 'application/json',
          },
          body: JSON.stringify({
            sessionId: sessionId.current,
            rrwebEvent: event,
            sequence: sequence,
          })
        });
      },
    });
  })

  return (
    <>
      <h2>Example elements</h2>
      <p>Some example elements to interact with.</p>
      <button className="btn">Click me</button>
      <input className="input" placeholder="Type something" />
      <select className="select">
        <option>Option 1</option>
        <option>Option 2</option>
      </select>
      <div className="checkbox">
        <label>
          <input type="checkbox" />
          <span>Checkbox</span>
        </label>
      </div>
      <div className="radio">
        <label className="radio">
          <input type="radio" name="radio" />
          <span>Radio 1</span>
        </label>
        <label className="radio">
          <input type="radio" name="radio" />
          <span>Radio 2</span>
        </label>
      </div>
    </>
  );
}

type Recordings = {
  Items: {
    sessionId: { "S": string },
    createdAt: { "N": string },
    screenshot: { "S": string },
  }[]
}

const useRecordings = (): { recordings: Recordings } => {
  // Query /recordings/ to get the list of recordings.
  const [recordings, setRecordings] = useState<Recordings>({ Items: [] });

  useEffect(() => {
    fetch(`${API_ROOT}/recordings/`)
      .then((response) => response.json())
      .then((data) => {
        setRecordings(data);
      });
  }, []);

  return { recordings };
}

const useRecordingEvents = (sessionId: string) => {
  // Get the events for a recording from /recordings/{sessionId}/events.
  const [events, setEvents] = useState<rrweb.EventType[]>([]);

  useEffect(() => {
    fetch(`${API_ROOT}/recordings/${sessionId}/events`, { mode: "cors" })
      // We get JSONL back from the endpoint, pull out each rrwebEvent from each
      // line and create an array of them.
      .then((response) => response.text())
      .then((data) => {
        const lines = data.split('\n');
        const events = lines.map((line) => {
          if (line.length > 0) {
            const event = JSON.parse(line);
            return event.rrwebEvent;
          }
        });
        setEvents(events);
      }
      );
  }, [sessionId]);

  return events;
}

const RecordingsListPage = () => {
  // Page that lists the recordings stored in IndexedDB to the left, and on
  // clicking on one, loads the player to the right. We link to the rrweb
  // recording playground page from here, opening it in a new tab.
  const { recordings } = useRecordings();
  const { sessionId } = useParams();

  return (
    <div className="flex">
      <div className="flex-1">
        <Link target="_blank" to="/session">Open rrweb recording playground</Link>
        <h2>Recordings</h2>
        <ul>
          {recordings.Items.map((recording) => (
            <li key={recording.sessionId.S}>
              <Link to={`/replay/${recording.sessionId.S}`}>{recording.sessionId.S}</Link>
            </li>
          ))}
        </ul>
      </div>
      <div className="flex-1">
        {sessionId ? (
          <>
            <h2>Player</h2>
            <RRWebPlayerComponent sessionId={sessionId} />
          </>
        ) : (
          <p>Select a recording to play.</p>
        )}
      </div>
    </div>
  );
}

const RRWebPlayerComponent = ({ sessionId }: { sessionId: string }) => {
  // Component to setup the rrweb player, and provide a ref to it to the parent
  // component so it can e.g. add events to it. We create a dedicated element to
  // pass in as the target to rrwebReplayer({target: ...}) and then pass the ref
  // to this player to the parent component.
  const playerElement = useRef<HTMLDivElement>(null);
  const playerRef = useRef<rrwebReplayer | null>(null);
  const events = useRecordingEvents(sessionId);

  useEffect(() => {
    if (playerElement.current && events.length > 2) {
      // If we have an element, create the player and set the ref. Note we use
      // live mode as documented here:
      // https://github.com/rrweb-io/rrweb/blob/master/docs/recipes/live-mode.md
      const player = playerRef.current = new rrwebReplayer({
        target: playerElement.current,
        props: {
          events: events,
          autoPlay: true,
        }
      });

      // Start the player.
      player.play();
    }

    return () => {
      // Cleanup the player and remove any elements that rrwebReplayer may have
      // added. I'm not 100% sure how to do this properly, but this seems to
      // work. It's possibly leaking memory though.
      if (playerRef.current) {
        playerRef.current.getReplayer().destroy();
        playerElement.current?.removeChild(playerElement.current?.firstChild!)
        playerRef.current = null;
      }
    }
  }, [playerElement.current, events]);

  // Render the player element
  return (
    <div className="rr-block" ref={playerElement} />
  );
}


export default App
