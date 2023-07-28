import * as rrweb from 'rrweb';
import html2canvas from 'html2canvas';

const sessionId = `${new Date().toISOString()}-${Math.random().toString(36).substring(7)}`;
const sequence = 0;
const API_ROOT = 'https://5c39zvs723.execute-api.us-east-1.amazonaws.com/prod'

export const createRecording = async () => {
    fetch(`${API_ROOT}/recordings/${sessionId}`, {
        method: 'PUT',
        mode: 'cors',
        headers: {
            'Content-Type': 'application/json',
        },
        body: JSON.stringify({
            sessionId: sessionId,
            screenshot: (await html2canvas(document.body)).toDataURL('image/jpeg', 0.1)
        })
    });
};

export const startRecording = async () => {
    rrweb.record({
        async emit(event) {
            await fetch(`${API_ROOT}/recordings/${sessionId}/events`, {
                method: 'POST',
                mode: 'cors',
                headers: {
                    'Content-Type': 'application/json',
                },
                body: JSON.stringify({
                    sessionId: sessionId,
                    rrwebEvent: event,
                    sequence: sequence,
                })
            });
        },
    });
}

