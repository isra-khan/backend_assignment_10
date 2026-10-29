// Question 3 - Manage Class Lists and Student Profiles
// You are updating a school's class management page. The school has two groups of students and wants to prepare
// updated data without accidentally changing the original lists or profile.
// Group A: ["Ali", "Ahmed", "Hamza"]
// Group B: ["Sara", "Ayesha", "Laiba"]
// Profile: { name: "Laiba", className: "Web Development", city: "Karachi" }
// - Create a combined class list containing the students from both groups.
// - Create an independent copy of Group A. Add a new student to the copy and show that the original Group A has not
// changed.
// - Create an updated profile for Laiba in which the city is changed to "Lahore" while the original profile remains
// unchanged.
// - Create another updated profile that keeps the existing details and adds a new property called email.
// - Display the original data and updated data so the differences are clear.



const profile = {
    name: "Laiba",
    className: "Web Development",
    city: "Karachi"
};

const groupA = ["Ali", "Ahmed", "Hamza"];
const groupB = ["Sara", "Ayesha", "Laiba"];

// Combine both groups
const combineList = [...groupA, ...groupB];
console.log("Combined list:", combineList);

// Copy Group A and add a student
const copyGroupA = [...groupA];
copyGroupA.push("Usman");

console.log("Original list:", groupA);
console.log("Copied list:", copyGroupA);

// Update city without changing the original profile
const updatedProfile = { ...profile, city: "Lahore" };

// Add email while keeping the original details
const newUpdatedProfile = {
    ...profile,
    email: "laiba@gmail.com"
};

console.log("Original profile:", profile);
console.log("Updated profile:", updatedProfile);
console.log("Profile with email:", newUpdatedProfile);
