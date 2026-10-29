// Question 1 - Library Book Record
// A library system receives book information from an older system as an ordered list. Use the sample record below and
// prepare the information needed for a book details card.
// Sample record: ["BK-104", "JavaScript for Beginners", "Programming", 1200]
// - Extract the book ID, book title, and price into separate variables.
// - Ignore the category value when extracting the details in one statement.
// - The system later receives a shorter record: ["BK-105", "Learning ES6"]. Prepare a category variable that uses
// "General" when the record does not include a category.
// - Display the extracted details in a readable sentence using a template literal.
// - Do not change the original arrays

const bookInfo=["BK-104", "JavaScript for Beginners", "Programming", 1200]
const [bookId, bookTitle,,bookPrice]=bookInfo;
shortRecord=["BK-105", "Learning ES6"];
const [,,category="general"]=shortRecord
console.log(`Book Id ${bookId}, Title ${bookTitle} , Book Price ${bookPrice}`);
console.log(`Category ${category}`);
