const chat = require('bdsx').chat;
chat.on(ev => {
    ev.setMessage(ev.message.toUpperCase() + " YEY!");
});